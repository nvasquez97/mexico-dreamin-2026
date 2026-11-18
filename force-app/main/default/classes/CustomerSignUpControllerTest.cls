/**
 * @description Tests of the customer sign-up (odd/tasks/req-005-customer-signup.md
 *              S2): CustomerSignUpController.signUp and the CustomerRegistration
 *              helper behind it. AC-005.1 (server), AC-005.2, AC-005.3 (server),
 *              AC-005.4 (server), AC-005.7 (the real site guest runs it) and
 *              AC-005.10 (server: a platform error never reaches the visitor).
 *              Site.validatePassword and Site.createExternalUser run through the
 *              CustomerRegistration.gateway seam; the user the seam "creates" is the
 *              seeded customer Marta Ruiz, because tests never insert portal users
 *              (3 free Customer Community seats, F7).
 */
@IsTest
private with sharing class CustomerSignUpControllerTest {

    // Test values of the password rule (AC-005.4), not credentials.
    private static final String VALID_PASS = 'abcd12345X';
    // Mixed case, inner and outer spaces: a lower-cased, trimmed or hard-coded
    // password reaching the platform turns the password tests red.
    private static final String OTHER_VALID_PASS = '  Zx9 Clave 7Q  ';
    private static final String BUSINESS_NAME = 'Ferretería Norte SA';
    private static final String TYPED_EMAIL = ' Luis.Garza@Example.com ';
    private static final String NORMALIZED_EMAIL = 'luis.garza@example.com';
    private static final String CODE_INVALID = 'INVALID';
    private static final String JOB_CLASS = 'CustomerPermissionAssigner';

    /** @description Queueable jobs the last guest sign-up enqueued. */
    private static Integer lastEnqueuedJobs = 0;

    /** @description The seam: records what the server passes to the platform. */
    private inherited sharing class FakeSite implements CustomerRegistration.SiteGateway {
        List<User> createdUsers = new List<User>();
        List<String> validatedPasswords = new List<String>();
        List<String> createdPasswords = new List<String>();
        List<Id> accountIds = new List<Id>();
        Boolean rejectPolicy = false;
        Boolean failCreate = false;
        String failCreateMessage = 'Simulated createExternalUser failure.';
        Boolean returnNoUser = false;
        Id userIdToReturn;

        public void validatePassword(User newUser, String pass) {
            validatedPasswords.add(pass);
            if (rejectPolicy) {
                throw new CustomerRegistration.RegistrationException('Policy rejected the test value.');
            }
        }

        public Id createExternalUser(User newUser, Id accountId, String pass) {
            if (failCreate) {
                throw new CustomerRegistration.RegistrationException(failCreateMessage);
            }
            createdUsers.add(newUser);
            accountIds.add(accountId);
            createdPasswords.add(pass);
            return returnNoUser ? null : userIdToReturn;
        }
    }

    /** @description The sign-up form, valid for a Business unless a test overrides a field. */
    private inherited sharing class SignUpForm {
        String customerType = 'Business';
        String accountName = BUSINESS_NAME;
        String firstName = 'Luis';
        String lastName = 'Garza';
        String email = TYPED_EMAIL;
        String phone = '81-5555-0101';
        String pass = VALID_PASS;
        String confirmation = VALID_PASS;

        CustomerSignUpController.SignUpResult submit() {
            Integer before = Limits.getQueueableJobs();
            CustomerSignUpController.SignUpResult result = CustomerSignUpController.signUp(
                customerType, accountName, firstName, lastName, email, phone, pass, confirmation
            );
            lastEnqueuedJobs = Limits.getQueueableJobs() - before;
            return result;
        }
    }

    private static FakeSite installFakeSite() {
        FakeSite fake = new FakeSite();
        fake.userIdToReturn = TestDataFactory.seededCustomerUser(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL).Id;
        CustomerRegistration.gateway = fake;
        return fake;
    }

    private static CustomerSignUpController.SignUpResult submitAsGuest(SignUpForm form) {
        CustomerSignUpController.SignUpResult result;
        System.runAs(TestDataFactory.siteGuestUser()) {
            result = form.submit();
        }
        return result;
    }

    private static Integer accountCount() {
        return [SELECT COUNT() FROM Account WITH SYSTEM_MODE];
    }

    private static Integer contactCount() {
        return [SELECT COUNT() FROM Contact WITH SYSTEM_MODE];
    }

    private static void assertNothingCreated(FakeSite fake, Integer accounts, Integer contacts) {
        Assert.areEqual(accounts, accountCount(), 'No Account may be created');
        Assert.areEqual(contacts, contactCount(), 'No Contact may be created');
        Assert.areEqual(0, fake.createdUsers.size(), 'createExternalUser must not be called');
        Assert.areEqual(0, lastEnqueuedJobs, 'No permission set job may be enqueued');
    }

    private static void assertRejected(SignUpForm form, String field, String message) {
        FakeSite fake = installFakeSite();
        CustomerSignUpController.SignUpResult result = submitAsGuest(form);
        Assert.isFalse(result.success, 'The sign-up must be rejected');
        Assert.areEqual(CODE_INVALID, result.code, 'A field validation code is expected');
        Assert.areEqual(field, result.field, 'The rejected field');
        Assert.areEqual(message, result.message, 'The generic message of the field');
        assertNothingCreated(fake, 0, 0);
    }

    private static void assertRegistered(SignUpForm form, Integer accounts, Integer contacts) {
        FakeSite fake = installFakeSite();
        CustomerSignUpController.SignUpResult result = submitAsGuest(form);
        Assert.isFalse(result.success, 'A registered email must not sign up again');
        Assert.areEqual(CustomerSignUpController.CODE_EMAIL_REGISTERED, result.code, 'The registered-email code');
        Assert.areEqual('email', result.field, 'The registered-email answer belongs to the email field');
        Assert.areEqual('This email is already registered. Log in instead.', result.message, 'The registered-email message');
        assertNothingCreated(fake, accounts, contacts);
    }

    private static void assertCreated(CustomerSignUpController.SignUpResult result) {
        Assert.isTrue(result.success, 'The sign-up must succeed: ' + result.message);
        Assert.areEqual(CustomerSignUpController.CODE_CREATED, result.code, 'The created code');
    }

    // ─── AC-005.1: server validation, generic message per field, nothing created ──

    @IsTest
    static void signUp_customerTypeOutsideList_isRejected() {
        // AC-005.1: a type outside {Individual, Business}
        SignUpForm form = new SignUpForm();
        form.customerType = 'Partner';
        assertRejected(form, 'customerType', CustomerSignUpController.MESSAGE_CUSTOMER_TYPE);
    }

    @IsTest
    static void signUp_customerTypeInOtherCase_isRejected() {
        // AC-005.1: the closed list is exact
        SignUpForm form = new SignUpForm();
        form.customerType = 'business';
        assertRejected(form, 'customerType', CustomerSignUpController.MESSAGE_CUSTOMER_TYPE);
    }

    @IsTest
    static void signUp_blankAccountName_isRejected() {
        // AC-005.1: a required field is empty
        SignUpForm form = new SignUpForm();
        form.accountName = '   ';
        assertRejected(form, 'accountName', CustomerSignUpController.MESSAGE_ACCOUNT_NAME);
    }

    @IsTest
    static void signUp_accountNameOver255_isRejected() {
        // AC-005.1: Account.Name holds 255 characters
        SignUpForm form = new SignUpForm();
        form.accountName = 'N'.repeat(256);
        assertRejected(form, 'accountName', CustomerSignUpController.MESSAGE_ACCOUNT_NAME);
    }

    @IsTest
    static void signUp_blankFirstName_isRejected() {
        // AC-005.1: a required field is empty
        SignUpForm form = new SignUpForm();
        form.firstName = null;
        assertRejected(form, 'firstName', CustomerSignUpController.MESSAGE_FIRST_NAME);
    }

    @IsTest
    static void signUp_firstNameOver40_isRejected() {
        // AC-005.1: Contact.FirstName holds 40 characters
        SignUpForm form = new SignUpForm();
        form.firstName = 'F'.repeat(41);
        assertRejected(form, 'firstName', CustomerSignUpController.MESSAGE_FIRST_NAME);
    }

    @IsTest
    static void signUp_blankLastName_isRejected() {
        // AC-005.1: a required field is empty
        SignUpForm form = new SignUpForm();
        form.lastName = '';
        assertRejected(form, 'lastName', CustomerSignUpController.MESSAGE_LAST_NAME);
    }

    @IsTest
    static void signUp_lastNameOver80_isRejected() {
        // AC-005.1: Contact.LastName holds 80 characters
        SignUpForm form = new SignUpForm();
        form.lastName = 'L'.repeat(81);
        assertRejected(form, 'lastName', CustomerSignUpController.MESSAGE_LAST_NAME);
    }

    @IsTest
    static void signUp_blankEmail_isRejected() {
        // AC-005.1: a required field is empty
        SignUpForm form = new SignUpForm();
        form.email = ' ';
        assertRejected(form, 'email', CustomerSignUpController.MESSAGE_EMAIL);
    }

    @IsTest
    static void signUp_malformedEmail_isRejected() {
        // AC-005.1: the email is malformed
        SignUpForm form = new SignUpForm();
        form.email = 'luis.garza@example';
        assertRejected(form, 'email', CustomerSignUpController.MESSAGE_EMAIL);
    }

    @IsTest
    static void signUp_email62Characters_isRejected() {
        // AC-005.1: 62 characters rejected (the username adds 19)
        SignUpForm form = new SignUpForm();
        form.email = 'a'.repeat(50) + '@example.com';
        assertRejected(form, 'email', CustomerSignUpController.MESSAGE_EMAIL);
    }

    @IsTest
    static void signUp_email61Characters_isAccepted() {
        // AC-005.1: 61 characters accepted
        FakeSite fake = installFakeSite();
        SignUpForm form = new SignUpForm();
        form.email = 'a'.repeat(49) + '@example.com';
        assertCreated(submitAsGuest(form));
        Assert.areEqual(form.email, fake.createdUsers[0].Email, 'The 61-character email reaches the user');
    }

    @IsTest
    static void signUp_blankPhone_isRejected() {
        // AC-005.1: a required field is empty
        SignUpForm form = new SignUpForm();
        form.phone = null;
        assertRejected(form, 'phone', CustomerSignUpController.MESSAGE_PHONE);
    }

    @IsTest
    static void signUp_phoneWithLetters_isRejected() {
        // AC-005.1: phone characters
        SignUpForm form = new SignUpForm();
        form.phone = '81-5555-CALL';
        assertRejected(form, 'phone', CustomerSignUpController.MESSAGE_PHONE);
    }

    @IsTest
    static void signUp_phoneOver40_isRejected() {
        // AC-005.1: Contact.Phone holds 40 characters
        SignUpForm form = new SignUpForm();
        form.phone = '8'.repeat(41);
        assertRejected(form, 'phone', CustomerSignUpController.MESSAGE_PHONE);
    }

    @IsTest
    static void signUp_nullCustomerType_isRejected() {
        // AC-005.1: the guest calls the @AuraEnabled method directly with no customer type
        SignUpForm form = new SignUpForm();
        form.customerType = null;
        assertRejected(form, 'customerType', CustomerSignUpController.MESSAGE_CUSTOMER_TYPE);
    }

    @IsTest
    static void signUp_nullPassword_isRejected() {
        // AC-005.4: the guest calls the @AuraEnabled method directly with no password
        SignUpForm form = new SignUpForm();
        form.pass = null;
        assertRejected(form, 'password', CustomerSignUpController.MESSAGE_PASS_RULES);
    }

    @IsTest
    static void signUp_nullConfirmPassword_isRejected() {
        // AC-005.4: the guest calls the @AuraEnabled method directly with no confirmation
        SignUpForm form = new SignUpForm();
        form.confirmation = null;
        assertRejected(form, 'confirmPassword', CustomerSignUpController.MESSAGE_CONFIRMATION);
    }

    // ─── AC-005.2: records and user built on the server ───────────────────

    @IsTest
    static void signUp_business_createsAccountWithNameAndType() {
        // AC-005.2: one Account (Name, Customer_Type__c) per sign-up
        installFakeSite();
        assertCreated(submitAsGuest(new SignUpForm()));
        List<Account> accounts = [SELECT Name, Customer_Type__c FROM Account WITH SYSTEM_MODE];
        Assert.areEqual(1, accounts.size(), 'One Account per sign-up');
        Assert.areEqual(BUSINESS_NAME, accounts[0].Name, 'Account name');
        Assert.areEqual('Business', accounts[0].Customer_Type__c, 'Customer type');
    }

    @IsTest
    static void signUp_business_createsContactWithNormalizedEmail() {
        // AC-005.2: one Contact (FirstName, LastName, Email lower case, Phone, AccountId)
        FakeSite fake = installFakeSite();
        assertCreated(submitAsGuest(new SignUpForm()));
        List<Contact> contacts = [SELECT FirstName, LastName, Email, Phone, AccountId FROM Contact WITH SYSTEM_MODE];
        Assert.areEqual(1, contacts.size(), 'One Contact per sign-up');
        Assert.areEqual('Luis', contacts[0].FirstName, 'First name');
        Assert.areEqual('Garza', contacts[0].LastName, 'Last name');
        Assert.areEqual(NORMALIZED_EMAIL, contacts[0].Email, 'Trimmed lower-case email');
        Assert.areEqual('81-5555-0101', contacts[0].Phone, 'Phone');
        Assert.areEqual(fake.accountIds[0], contacts[0].AccountId, 'The Contact belongs to the new Account');
    }

    @IsTest
    static void signUp_individual_createsAccountAndContactWithItsValues() {
        // AC-005.2: an Individual sign-up (second input)
        installFakeSite();
        SignUpForm form = new SignUpForm();
        form.customerType = 'Individual';
        form.accountName = 'Sofía Treviño';
        form.firstName = 'Sofía';
        form.lastName = 'Treviño';
        form.email = 'SOFIA.T@Correo.MX';
        form.phone = '+52 55 1234 5678';
        assertCreated(submitAsGuest(form));
        Contact person = [SELECT FirstName, LastName, Email, Phone, Account.Name, Account.Customer_Type__c FROM Contact WITH SYSTEM_MODE];
        Assert.areEqual('Individual', person.Account.Customer_Type__c, 'Customer type');
        Assert.areEqual('Sofía Treviño', person.Account.Name, 'Account name');
        Assert.areEqual('sofia.t@correo.mx', person.Email, 'Lower-case email');
        Assert.areEqual('+52 55 1234 5678', person.Phone, 'Phone');
        Assert.areEqual('Sofía', person.FirstName, 'First name');
    }

    @IsTest
    static void signUp_buildsUsernameAndEmailOnTheServer() {
        // AC-005.2: username = normalized email + "." + 18-char org Id lower case
        FakeSite fake = installFakeSite();
        assertCreated(submitAsGuest(new SignUpForm()));
        User newUser = fake.createdUsers[0];
        Assert.areEqual(NORMALIZED_EMAIL + '.' + UserInfo.getOrganizationId().toLowerCase(), newUser.Username, 'Username');
        Assert.areEqual(18, UserInfo.getOrganizationId().length(), 'The org Id in the username has 18 characters');
        Assert.areEqual(NORMALIZED_EMAIL, newUser.Email, 'Lower-case email');
        Assert.areEqual('Luis', newUser.FirstName, 'First name');
        Assert.areEqual('Garza', newUser.LastName, 'Last name');
    }

    @IsTest
    static void signUp_passesNewContactProfileAndLocaleToCreateExternalUser() {
        // AC-005.2: ContactId of the new Contact, ProfileId from the server, locale fields
        FakeSite fake = installFakeSite();
        assertCreated(submitAsGuest(new SignUpForm()));
        User newUser = fake.createdUsers[0];
        Contact person = [SELECT Id, AccountId FROM Contact WITH SYSTEM_MODE];
        Id profileId = [SELECT Id FROM Profile WHERE Name = :TestDataFactory.CUSTOMER_PROFILE_NAME WITH SYSTEM_MODE].Id;
        Assert.areEqual(person.Id, newUser.ContactId, 'ContactId of the new Contact');
        Assert.areEqual(person.AccountId, fake.accountIds[0], 'createExternalUser gets the new Account');
        Assert.areEqual(profileId, newUser.ProfileId, 'ProfileId of RutaCargo Customer');
        Assert.areEqual('America/Mexico_City', newUser.TimeZoneSidKey, 'Time zone');
        Assert.areEqual('es_MX', newUser.LocaleSidKey, 'Locale');
        Assert.areEqual('en_US', newUser.LanguageLocaleKey, 'Language');
        Assert.areEqual('UTF-8', newUser.EmailEncodingKey, 'Email encoding');
    }

    @IsTest
    static void signUp_buildsAliasOfAtMostEightCharacters() {
        // AC-005.2: Alias = first 4 letters of the local part + 4 random characters
        FakeSite fake = installFakeSite();
        assertCreated(submitAsGuest(new SignUpForm()));
        String alias = fake.createdUsers[0].Alias;
        Assert.areEqual(8, alias.length(), 'Alias length: ' + alias);
        Assert.isTrue(alias.startsWith('luis'), 'Alias starts with the local part letters: ' + alias);
    }

    @IsTest
    static void signUp_sameLocalPart_buildsDifferentNicknames() {
        // AC-005.2: CommunityNickname unique for ana@x.com and ana@y.com
        FakeSite fake = installFakeSite();
        SignUpForm first = new SignUpForm();
        first.email = 'ana@x.com';
        SignUpForm second = new SignUpForm();
        second.email = 'ana@y.com';
        assertCreated(submitAsGuest(first));
        assertCreated(submitAsGuest(second));
        String firstNickname = fake.createdUsers[0].CommunityNickname;
        String secondNickname = fake.createdUsers[1].CommunityNickname;
        Assert.areNotEqual(firstNickname, secondNickname, 'Nicknames differ for the same local part');
    }

    @IsTest
    static void signUp_nickname_neverContainsTheEmailLocalPart() {
        // AC-005.2 (F11): the site displays nicknames, so the nickname is random, not the email's local part
        FakeSite fake = installFakeSite();
        SignUpForm first = new SignUpForm();
        first.email = 'ana@x.com';
        SignUpForm second = new SignUpForm();
        assertCreated(submitAsGuest(first));
        assertCreated(submitAsGuest(second));
        assertRandomNickname(fake.createdUsers[0].CommunityNickname, 'ana');
        assertRandomNickname(fake.createdUsers[1].CommunityNickname, 'luis.garza');
    }

    private static void assertRandomNickname(String nickname, String localPart) {
        Assert.isTrue(Pattern.matches('customer-[0-9a-f]{12}', nickname), 'Nickname = "customer-" + 12 random hex characters: ' + nickname);
        Assert.isFalse(nickname.containsIgnoreCase(localPart), 'The email local part "' + localPart + '" is not in the nickname: ' + nickname);
    }

    @IsTest
    static void signUp_enqueuesAssignerThatAssignsCustomerPermissionSet() {
        // AC-005.2: a CustomerPermissionAssigner job is enqueued and assigns RutaCargo_Customer
        FakeSite fake = installFakeSite();
        TestDataFactory.removePermissionSetAssignment(fake.userIdToReturn, TestDataFactory.CUSTOMER_PERMISSION_SET);
        Datetime startedAt = Datetime.now().addSeconds(-1);
        Test.startTest();
        assertCreated(submitAsGuest(new SignUpForm()));
        Test.stopTest();
        Assert.areEqual(1, lastEnqueuedJobs, 'One job enqueued');
        Assert.areEqual(1, [SELECT COUNT() FROM AsyncApexJob
                WHERE ApexClass.Name = :JOB_CLASS AND Status = 'Completed' AND CreatedDate >= :startedAt WITH SYSTEM_MODE],
            'The CustomerPermissionAssigner job completed');
        Assert.areEqual(1, [SELECT COUNT() FROM PermissionSetAssignment
                WHERE AssigneeId = :fake.userIdToReturn AND PermissionSet.Name = :TestDataFactory.CUSTOMER_PERMISSION_SET WITH SYSTEM_MODE],
            'The new user has RutaCargo_Customer');
    }

    @IsTest
    static void assigner_internalUser_assignsNothing() {
        // AC-005.2: the job assigns RutaCargo_Customer only to a RutaCargo Customer user
        Id adminId = UserInfo.getUserId();
        Test.startTest();
        System.enqueueJob(new CustomerPermissionAssigner(adminId));
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM PermissionSetAssignment
                WHERE AssigneeId = :adminId AND PermissionSet.Name = :TestDataFactory.CUSTOMER_PERMISSION_SET WITH SYSTEM_MODE],
            'An internal user never gets the customer permission set');
    }

    @IsTest
    static void assigner_customerAlreadyAssigned_keepsOneAssignment() {
        // AC-005.2: the job assigns only once
        Id martaId = TestDataFactory.seededCustomerUser(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL).Id;
        Test.startTest();
        System.enqueueJob(new CustomerPermissionAssigner(martaId));
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM PermissionSetAssignment
                WHERE AssigneeId = :martaId AND PermissionSet.Name = :TestDataFactory.CUSTOMER_PERMISSION_SET WITH SYSTEM_MODE],
            'Still exactly one assignment');
    }

    @IsTest
    static void signUp_createExternalUserThrows_rollsBackAndReturnsGenericMessage() {
        // AC-005.2: createExternalUser fails → Account and Contact rolled back, no job
        FakeSite fake = installFakeSite();
        fake.failCreate = true;
        CustomerSignUpController.SignUpResult result = submitAsGuest(new SignUpForm());
        Assert.isFalse(result.success, 'The sign-up fails');
        Assert.areEqual(CustomerSignUpController.CODE_FAILED, result.code, 'Failure code');
        Assert.areEqual(CustomerSignUpController.MESSAGE_FAILED, result.message, 'Generic message');
        Assert.isNull(result.field, 'No field is blamed');
        assertNothingCreated(fake, 0, 0);
    }

    @IsTest
    static void signUp_ownerReportedPlatformError_returnsOnlyTheGenericMessage() {
        // AC-005.10: the platform text the owner reported never reaches the visitor
        assertPlatformErrorIsHidden('[accountId parameter value is not valid.]');
    }

    @IsTest
    static void signUp_privilegePlatformError_returnsOnlyTheGenericMessage() {
        // AC-005.10: another platform text (second input) never reaches the visitor
        assertPlatformErrorIsHidden('Insufficient Privileges: You do not have the level of access necessary to perform the operation you requested.');
    }

    private static void assertPlatformErrorIsHidden(String platformText) {
        FakeSite fake = installFakeSite();
        fake.failCreate = true;
        fake.failCreateMessage = platformText;
        CustomerSignUpController.SignUpResult result = submitAsGuest(new SignUpForm());
        Assert.areEqual(CustomerSignUpController.CODE_FAILED, result.code, 'Failure code');
        Assert.areEqual(CustomerSignUpController.MESSAGE_FAILED, result.message, 'Only the generic message is returned');
        Assert.isFalse(result.message.contains(platformText), 'The platform text is never returned');
        Assert.isNull(result.field, 'No field is blamed');
        assertNothingCreated(fake, 0, 0);
    }

    @IsTest
    static void signUp_createExternalUserReturnsNoUser_rollsBack() {
        // AC-005.2: a null user Id is a failure too (second input)
        FakeSite fake = installFakeSite();
        fake.returnNoUser = true;
        CustomerSignUpController.SignUpResult result = submitAsGuest(new SignUpForm());
        Assert.areEqual(CustomerSignUpController.MESSAGE_FAILED, result.message, 'Generic message');
        Assert.areEqual(0, accountCount(), 'Account rolled back');
        Assert.areEqual(0, contactCount(), 'Contact rolled back');
        Assert.areEqual(0, lastEnqueuedJobs, 'No job enqueued');
    }

    @IsTest
    static void signUp_asAdmin_createsTheCustomer() {
        // AC-005.2: the same server path for an internal caller
        FakeSite fake = installFakeSite();
        SignUpForm form = new SignUpForm();
        form.email = 'admin.path@example.com';
        assertCreated(form.submit());
        Assert.areEqual(1, accountCount(), 'One Account');
        Assert.areEqual('admin.path@example.com', fake.createdUsers[0].Email, 'The user is built');
    }

    // ─── AC-005.3: one account per email, trimmed and in any case ─────────

    @IsTest
    static void signUp_seededCustomerEmailTrimmedMixedCase_isRegistered() {
        // AC-005.3: " Ana.Lopez@Example.com " belongs to a customer user
        SignUpForm form = new SignUpForm();
        form.email = ' Ana.Lopez@Example.com ';
        assertRegistered(form, 0, 0);
    }

    @IsTest
    static void signUp_emailOfCustomerContactOnly_isRegistered() {
        // AC-005.3: a RutaCargo customer contact (no user) with the email
        Account customer = TestDataFactory.insertCustomerAccount('Abarrotes Prueba');
        TestDataFactory.insertCustomerContact(customer.Id, NORMALIZED_EMAIL);
        assertRegistered(new SignUpForm(), 1, 1);
    }

    @IsTest
    static void signUp_emailOfInactiveCustomerUser_isRegistered() {
        // AC-005.3: the email of an INACTIVE customer user
        User marta = TestDataFactory.seededCustomerUser(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL);
        TestDataFactory.deactivateUser(marta.Id);
        SignUpForm form = new SignUpForm();
        form.email = 'Marta.Ruiz@example.com';
        assertRegistered(form, 0, 0);
    }

    // ─── AC-005.4: server password rules ──────────────────────────────────

    @IsTest
    static void signUp_passwordOfNineCharacters_isRejected() {
        // AC-005.4: "abc123def" (9)
        SignUpForm form = new SignUpForm();
        form.pass = 'abc123def';
        form.confirmation = form.pass;
        assertRejected(form, 'password', CustomerSignUpController.MESSAGE_PASS_RULES);
    }

    @IsTest
    static void signUp_passwordWithoutDigit_isRejected() {
        // AC-005.4: "abcdefghij" (no digit)
        SignUpForm form = new SignUpForm();
        form.pass = 'abcdefghij';
        form.confirmation = form.pass;
        assertRejected(form, 'password', CustomerSignUpController.MESSAGE_PASS_RULES);
    }

    @IsTest
    static void signUp_passwordWithoutLetter_isRejected() {
        // AC-005.4: "1234567890" (no letter)
        SignUpForm form = new SignUpForm();
        form.pass = '1234567890';
        form.confirmation = form.pass;
        assertRejected(form, 'password', CustomerSignUpController.MESSAGE_PASS_RULES);
    }

    @IsTest
    static void signUp_confirmationDiffersInCase_isRejected() {
        // AC-005.4: a confirmation that differs (only in case: the comparison is exact)
        SignUpForm form = new SignUpForm();
        form.confirmation = VALID_PASS.toLowerCase();
        assertRejected(form, 'confirmPassword', CustomerSignUpController.MESSAGE_CONFIRMATION);
    }

    @IsTest
    static void signUp_passwordOfTenWithLettersAndDigits_isAccepted() {
        // AC-005.4: "abcd12345X" is accepted and reaches the platform unchanged
        assertPasswordReachesPlatformUnchanged(VALID_PASS);
    }

    @IsTest
    static void signUp_passwordWithSpacesAndMixedCase_reachesPlatformUnchanged() {
        // AC-005.4: a second accepted password (spaces, mixed case) reaches the platform unchanged
        assertPasswordReachesPlatformUnchanged(OTHER_VALID_PASS);
    }

    @IsTest
    static void signUp_passwordOf128Characters_isAccepted() {
        // AC-005.1: a password at its maximum length (128) is accepted
        assertPasswordReachesPlatformUnchanged('a'.repeat(127) + '9');
    }

    @IsTest
    static void signUp_passwordOf129Characters_isRejected() {
        // AC-005.1: a password longer than its maximum (129) is rejected
        SignUpForm form = new SignUpForm();
        form.pass = 'a'.repeat(128) + '9';
        form.confirmation = form.pass;
        assertRejected(form, 'password', CustomerSignUpController.MESSAGE_PASS_RULES);
    }

    /** @description Signs up with the password and checks both seam calls got exactly it (case-sensitive). */
    private static void assertPasswordReachesPlatformUnchanged(String typed) {
        FakeSite fake = installFakeSite();
        SignUpForm form = new SignUpForm();
        form.pass = typed;
        form.confirmation = typed;
        assertCreated(submitAsGuest(form));
        Assert.areEqual(1, fake.validatedPasswords.size(), 'Site.validatePassword is called once');
        Assert.areEqual(1, fake.createdPasswords.size(), 'Site.createExternalUser is called once');
        Assert.isTrue(typed.equals(fake.validatedPasswords[0]), 'Site.validatePassword gets the typed password exactly');
        Assert.isTrue(typed.equals(fake.createdPasswords[0]), 'Site.createExternalUser gets the typed password exactly');
    }

    @IsTest
    static void signUp_sitePolicyRejectsPassword_isRejected() {
        // AC-005.4: Site.validatePassword (the profile's policy) rejects it
        FakeSite fake = installFakeSite();
        fake.rejectPolicy = true;
        CustomerSignUpController.SignUpResult result = submitAsGuest(new SignUpForm());
        Assert.isFalse(result.success, 'Rejected by the policy');
        Assert.areEqual('password', result.field, 'Password field');
        Assert.areEqual(CustomerSignUpController.MESSAGE_PASS_POLICY, result.message, 'Policy message');
        assertNothingCreated(fake, 0, 0);
    }
}
