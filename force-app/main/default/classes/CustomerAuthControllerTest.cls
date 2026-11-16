/**
 * Tests for CustomerAuthController (sign-up, login, forgot password), run as
 * the real site guest. Site.* methods do not work in Apex tests, so a fake
 * SiteGateway records what the controller asks the platform to do.
 * Covers AC-005.1 to AC-005.6.
 */
@IsTest
private class CustomerAuthControllerTest {
    private static final String PASSWORD = 'Cargo2026xyz';

    /** Fake platform: records calls and returns fixed values or fails on demand. */
    private class FakeGateway extends SiteGateway {
        User createdUser;
        Id createdForAccount;
        String createdWithPassword;
        String loggedInAs;
        String forgotFor;
        Boolean failCreate = false;
        Boolean failLogin = false;

        public override Id createExternalUser(User newUser, Id accountId, String password) {
            if (failCreate) {
                throw new SiteGateway.SiteGatewayException('platform rejected the user');
            }
            createdUser = newUser;
            createdForAccount = accountId;
            createdWithPassword = password;
            return UserInfo.getUserId();
        }

        public override String login(String username, String password, String startUrl) {
            if (failLogin) {
                throw new SiteGateway.SiteGatewayException('Your login attempt has failed');
            }
            loggedInAs = username;
            return 'https://example.com/secur/frontdoor.jsp?startURL=' + startUrl;
        }

        public override Boolean forgotPassword(String username) {
            forgotFor = username;
            return true;
        }
    }

    @TestSetup
    static void setup() {
        User owner = TestDataFactory.createAccountOwner('RegOwner');
        Database.insert(new RutaCargo_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Account_Owner_Id__c = owner.Id), AccessLevel.SYSTEM_MODE);
        Account existing = TestDataFactory.buildCustomerAccount('Existing Customer');
        existing.OwnerId = owner.Id;
        Database.insert(existing, AccessLevel.SYSTEM_MODE);
        Database.insert(new Contact(AccountId = existing.Id, FirstName = 'Ana', LastName = 'Lopez', Email = 'ana.lopez@example.com'), AccessLevel.SYSTEM_MODE);
    }

    private static FakeGateway useFakeGateway() {
        FakeGateway fake = new FakeGateway();
        CustomerAuthController.gateway = fake;
        return fake;
    }

    private static CustomerAuthController.AuthResult registerAsGuest(String customerType, String accountName, String email, String password) {
        CustomerAuthController.AuthResult result;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            result = CustomerAuthController.register(customerType, accountName, 'Marta', 'Ruiz', email, '+52 55 5555 0199', password);
        }
        return result;
    }

    private static List<Account> accountsNamed(String name) {
        return [SELECT Id, Name, Customer_Type__c, OwnerId FROM Account WHERE Name = :name WITH SYSTEM_MODE];
    }

    // Covers AC-005.1, AC-005.2: sign-up creates the account with its contact and asks the platform for the site user.
    @IsTest
    static void shouldCreateAccountContactAndUser_WhenBusinessSignsUp() {
        FakeGateway fake = useFakeGateway();
        Test.startTest();
        CustomerAuthController.AuthResult result = registerAsGuest('Business', 'Globex Test SA', 'Marta.Ruiz@Example.com', PASSWORD);
        Test.stopTest();
        Assert.isTrue(result.success, 'Signed up: ' + result.message);
        List<Account> created = accountsNamed('Globex Test SA');
        Assert.areEqual(1, created.size(), 'Account created');
        Assert.areEqual('Business', created[0].Customer_Type__c, 'Customer type');
        Contact person = [SELECT FirstName, LastName, Email, Phone, AccountId FROM Contact WHERE AccountId = :created[0].Id WITH SYSTEM_MODE];
        Assert.areEqual('Marta', person.FirstName, 'First name');
        Assert.areEqual('Ruiz', person.LastName, 'Last name');
        Assert.areEqual('marta.ruiz@example.com', person.Email, 'Email normalized');
        Assert.areEqual('+52 55 5555 0199', person.Phone, 'Phone');
        Assert.areEqual(created[0].Id, fake.createdForAccount, 'User created for the new account');
        Assert.areEqual(person.Id, fake.createdUser.ContactId, 'User linked to the contact');
        Assert.areEqual('marta.ruiz@example.com.rutacargo', fake.createdUser.Username, 'Username derived from the email');
        Assert.areEqual(PASSWORD, fake.createdWithPassword, 'Password handed to the platform only');
    }

    // Covers AC-005.2: the account is owned by the configured internal owner (portal accounts need an owner with a role).
    @IsTest
    static void shouldAssignConfiguredOwner_WhenSigningUp() {
        useFakeGateway();
        registerAsGuest('Individual', 'Marta Ruiz', 'marta.ruiz@example.com', PASSWORD);
        Id expectedOwner = RutaCargo_Settings__c.getOrgDefaults().Account_Owner_Id__c;
        Assert.areEqual(expectedOwner, accountsNamed('Marta Ruiz')[0].OwnerId, 'Configured owner');
        Assert.areEqual('Individual', accountsNamed('Marta Ruiz')[0].Customer_Type__c, 'Individual type');
    }

    // Covers AC-005.5: after sign-up the customer is logged in and sent to My Shipments.
    @IsTest
    static void shouldLogInAfterSignUp_WhenUserCreated() {
        FakeGateway fake = useFakeGateway();
        CustomerAuthController.AuthResult result = registerAsGuest('Business', 'Globex Test SA', 'marta.ruiz@example.com', PASSWORD);
        Assert.areEqual('marta.ruiz@example.com.rutacargo', fake.loggedInAs, 'Logged in with the new user');
        Assert.isTrue(result.redirectUrl.contains('my-shipments'), 'Redirect to My Shipments: ' + result.redirectUrl);
    }

    // Covers AC-005.2: the customer permission set is assigned asynchronously (setup DML cannot mix with the account).
    @IsTest
    static void shouldQueueCustomerAccess_WhenUserCreated() {
        useFakeGateway();
        Integer queued;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            CustomerAuthController.register('Business', 'Globex Test SA', 'Marta', 'Ruiz', 'marta.ruiz@example.com', '5555550199', PASSWORD);
            queued = Limits.getQueueableJobs();
        }
        Assert.areEqual(1, queued, 'One access job queued');
    }

    // Covers AC-005.3: an email that already has an account is rejected and login is offered.
    @IsTest
    static void shouldOfferLogin_WhenEmailAlreadyRegistered() {
        FakeGateway fake = useFakeGateway();
        CustomerAuthController.AuthResult result = registerAsGuest('Business', 'Duplicate SA', '  ANA.LOPEZ@example.com ', PASSWORD);
        Assert.isFalse(result.success, 'Rejected');
        Assert.isTrue(result.emailAlreadyRegistered, 'Login offered');
        Assert.areEqual('This email is already registered. Log in instead.', result.message, 'Message');
        Assert.areEqual(0, accountsNamed('Duplicate SA').size(), 'No account created');
        Assert.isNull(fake.createdUser, 'No user requested');
    }

    // Covers AC-005.4: fewer than 10 characters is rejected.
    @IsTest
    static void shouldReject_WhenPasswordShorterThanTen() {
        assertPasswordRejected('Cargo2026');
    }

    // Covers AC-005.4: letters without numbers is rejected.
    @IsTest
    static void shouldReject_WhenPasswordHasNoNumbers() {
        assertPasswordRejected('CargoCargoCargo');
    }

    // Covers AC-005.4: numbers without letters is rejected.
    @IsTest
    static void shouldReject_WhenPasswordHasNoLetters() {
        assertPasswordRejected('12345678901');
    }

    private static void assertPasswordRejected(String password) {
        FakeGateway fake = useFakeGateway();
        CustomerAuthController.AuthResult result = registerAsGuest('Business', 'Weak Password SA', 'weak@example.com', password);
        Assert.isFalse(result.success, 'Rejected');
        Assert.areEqual('The password must have at least 10 characters, with letters and numbers.', result.message, 'Message');
        Assert.areEqual(0, accountsNamed('Weak Password SA').size(), 'No account created');
        Assert.isNull(fake.createdUser, 'No user requested');
    }

    // Covers AC-005.1: customer type must be Individual or Business.
    @IsTest
    static void shouldReject_WhenCustomerTypeInvalid() {
        useFakeGateway();
        CustomerAuthController.AuthResult result = registerAsGuest('Partner', 'Bad Type SA', 'type@example.com', PASSWORD);
        Assert.isFalse(result.success, 'Rejected');
        Assert.areEqual(0, accountsNamed('Bad Type SA').size(), 'No account created');
    }

    // Covers AC-005.1: an invalid email is rejected.
    @IsTest
    static void shouldReject_WhenEmailInvalid() {
        useFakeGateway();
        CustomerAuthController.AuthResult result = registerAsGuest('Business', 'Bad Email SA', 'not-an-email', PASSWORD);
        Assert.isFalse(result.success, 'Rejected');
        Assert.areEqual('Enter a valid email.', result.message, 'Message');
    }

    // Covers AC-005.1: a missing name or legal name is rejected.
    @IsTest
    static void shouldReject_WhenAccountNameMissing() {
        useFakeGateway();
        CustomerAuthController.AuthResult result = registerAsGuest('Business', '   ', 'blank@example.com', PASSWORD);
        Assert.isFalse(result.success, 'Rejected');
    }

    // Covers AC-005.2: if the platform cannot create the user, nothing is left behind and the message is generic.
    @IsTest
    static void shouldRollBack_WhenPlatformRejectsUser() {
        FakeGateway fake = useFakeGateway();
        fake.failCreate = true;
        CustomerAuthController.AuthResult result = registerAsGuest('Business', 'Rollback SA', 'rollback@example.com', PASSWORD);
        Assert.isFalse(result.success, 'Failed');
        Assert.areEqual(0, accountsNamed('Rollback SA').size(), 'Account rolled back');
        Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE Email = 'rollback@example.com' WITH SYSTEM_MODE], 'Contact rolled back');
        Assert.isFalse(result.message.contains('platform rejected'), 'Internal message not shown');
    }

    // Covers AC-005.5: login uses the email and returns where to go.
    @IsTest
    static void shouldLogIn_WhenCredentialsValid() {
        FakeGateway fake = useFakeGateway();
        CustomerAuthController.AuthResult result;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            result = CustomerAuthController.login(' Ana.Lopez@example.com ', PASSWORD);
        }
        Assert.isTrue(result.success, 'Logged in');
        Assert.areEqual('ana.lopez@example.com.rutacargo', fake.loggedInAs, 'Username derived from the email');
        Assert.isNotNull(result.redirectUrl, 'Redirect URL');
    }

    // Covers AC-005.5: wrong credentials get a generic message.
    @IsTest
    static void shouldShowGenericMessage_WhenLoginFails() {
        FakeGateway fake = useFakeGateway();
        fake.failLogin = true;
        CustomerAuthController.AuthResult result;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            result = CustomerAuthController.login('ana.lopez@example.com', 'wrong');
        }
        Assert.isFalse(result.success, 'Not logged in');
        Assert.areEqual('Invalid email or password.', result.message, 'Generic message');
    }

    // Covers AC-005.6: forgot password asks the platform to email a reset link, with a message that does not reveal accounts.
    @IsTest
    static void shouldRequestResetLink_WhenForgotPassword() {
        FakeGateway fake = useFakeGateway();
        CustomerAuthController.AuthResult result;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            result = CustomerAuthController.forgotPassword('Ana.Lopez@example.com');
        }
        Assert.areEqual('ana.lopez@example.com.rutacargo', fake.forgotFor, 'Reset requested for the derived username');
        Assert.areEqual('If the email is registered, you will receive a link to reset your password.', result.message, 'Neutral message');
    }

    // Covers AC-005.6: an invalid email still gets the neutral message and no reset request.
    @IsTest
    static void shouldNotRequestReset_WhenEmailInvalid() {
        FakeGateway fake = useFakeGateway();
        CustomerAuthController.AuthResult result;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            result = CustomerAuthController.forgotPassword('nope');
        }
        Assert.isNull(fake.forgotFor, 'No reset request');
        Assert.isTrue(result.success, 'Neutral success');
    }

    // Covers AC-005.1: a missing contact last name is rejected and nothing is created.
    @IsTest
    static void shouldReject_WhenContactLastNameMissing() {
        FakeGateway fake = useFakeGateway();
        CustomerAuthController.AuthResult result;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            result = CustomerAuthController.register('Business', 'No Last Name SA', 'Marta', '  ', 'nolast@example.com', '+52 55 5555 0199', PASSWORD);
        }
        Assert.areEqual('Enter the first and last name of the contact person.', result.message, 'Message');
        Assert.areEqual(0, accountsNamed('No Last Name SA').size(), 'No account created');
        Assert.isNull(fake.createdUser, 'No user requested');
    }

    // Covers AC-005.1: an invalid phone is rejected and nothing is created.
    @IsTest
    static void shouldReject_WhenPhoneInvalid() {
        FakeGateway fake = useFakeGateway();
        CustomerAuthController.AuthResult result;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            result = CustomerAuthController.register('Business', 'Bad Phone SA', 'Marta', 'Ruiz', 'badphone@example.com', 'call me', PASSWORD);
        }
        Assert.areEqual('Enter a valid phone number.', result.message, 'Message');
        Assert.areEqual(0, accountsNamed('Bad Phone SA').size(), 'No account created');
        Assert.isNull(fake.createdUser, 'No user requested');
    }

    // Covers AC-005.3: an email already used by a site username (with no matching contact email) is rejected.
    @IsTest
    static void shouldOfferLogin_WhenEmailIsAlreadyASiteUsername() {
        User owner = [SELECT Id FROM User WHERE LastName = 'Owner RegOwner' LIMIT 1];
        User existing = TestDataFactory.createCustomerUser('Username Taken SA', 'Takenuser', 'RutaCargo_Customer', owner);
        existing.Username = 'taken.user@example.com' + CustomerAuthController.USERNAME_SUFFIX;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Database.update(existing, AccessLevel.SYSTEM_MODE);
        }
        FakeGateway fake = useFakeGateway();
        CustomerAuthController.AuthResult result = registerAsGuest('Business', 'Second Try SA', 'Taken.User@example.com', PASSWORD);
        Assert.isTrue(result.emailAlreadyRegistered, 'Login offered');
        Assert.areEqual(0, accountsNamed('Second Try SA').size(), 'No account created');
        Assert.isNull(fake.createdUser, 'No user requested');
    }

    // Covers AC-005.5: an invalid email or a blank password is rejected without calling the platform.
    @IsTest
    static void shouldRejectLogin_WhenEmailInvalidOrPasswordBlank() {
        FakeGateway fake = useFakeGateway();
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            Assert.areEqual('Invalid email or password.', CustomerAuthController.login('not-an-email', PASSWORD).message, 'Invalid email');
            Assert.areEqual('Invalid email or password.', CustomerAuthController.login('ana.lopez@example.com', '').message, 'Blank password');
        }
        Assert.isNull(fake.loggedInAs, 'Platform login never called');
    }
}
