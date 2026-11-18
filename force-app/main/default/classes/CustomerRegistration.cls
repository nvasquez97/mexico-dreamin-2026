/**
 * @description System-mode helper of the customer sign-up, login and password
 *              reset (odd/tasks/req-005-customer-signup.md S2, S3). It is not a
 *              guest entry point: only CustomerSignUpController and
 *              CustomerLoginController call it, after validating every field.
 *              It receives individual strings (never an SObject, an Id or a
 *              profile from the client), binds every value, resolves the profile
 *              from the constant name "RutaCargo Customer" on the server and
 *              returns an outcome or a username, never a record.
 */
// SECURITY-JUSTIFICATION: the site guest (no object permissions, no access to
// other users' records) must check that an email is not registered (Contact.Email
// of customer accounts, User.Email of active and inactive customer users), insert
// the customer's Account and Contact before Site.createExternalUser, and map a
// customer's email to its username for Site.login and Site.forgotPassword. That
// needs reads and writes without sharing and in system mode (WITH SYSTEM_MODE,
// AccessLevel.SYSTEM_MODE: at API 67 user mode is the default). Scope: this class
// only; its callers are CustomerSignUpController and CustomerLoginController (both
// with sharing). Compensating controls: server-side validation of every field in
// the callers; binds only; the User is built here (profile from the constant name,
// username from the normalized email and the org Id); lookups never resolve a
// user outside the profile "RutaCargo Customer"; a savepoint rolls back the
// Account and Contact on any failure; the guest has class access only to the two
// controllers (guest-access-check.sh, customer-access-check.sh).
// (pending owner approval, 2026-11-17)
public without sharing class CustomerRegistration {

    /** @description The only profile a sign-up creates and a login or reset resolves. */
    public static final String CUSTOMER_PROFILE_NAME = 'RutaCargo Customer';

    private static final Integer MAX_EMAIL_LENGTH = 80;
    private static final Integer NICKNAME_PREFIX_LENGTH = 30;
    private static final Integer NICKNAME_RANDOM_LENGTH = 6;
    private static final Integer ALIAS_LETTERS = 4;
    private static final Integer ALIAS_RANDOM_LENGTH = 4;

    /** @description The result of a registration. */
    public enum Outcome { CREATED, REGISTERED, INVALID_PASSWORD, FAILED }

    /**
     * @description The platform calls of a registration. Tests replace it
     *              (@TestVisible seam): Site.createExternalUser cannot run in a test.
     */
    public interface SiteGateway {
        /**
         * @description Throws when the password does not meet the policy of the user's profile.
         * @param newUser the unsaved user
         * @param password the password
         */
        void validatePassword(User newUser, String password);

        /**
         * @description Creates the external user for the account.
         * @param newUser the unsaved user
         * @param accountId the customer's account
         * @param password the password
         * @return the new user's Id, or null when no user was created
         */
        Id createExternalUser(User newUser, Id accountId, String password);
    }

    @TestVisible
    private static SiteGateway gateway = new PlatformSiteGateway();

    /** @description A registration failure (and the seam's failures in tests). */
    public class RegistrationException extends Exception {}

    /**
     * @description The validated sign-up values, built by CustomerSignUpController
     *              on the server from individual fields (never an SObject).
     */
    public class Applicant {
        public String customerType;
        public String accountName;
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
    }

    /**
     * @description The one email normalization of sign-up, login and reset:
     *              trimmed and in lower case.
     * @param email the email as typed
     * @return the normalized email, or null for a null email
     */
    public static String normalizeEmail(String email) {
        return email == null ? null : email.trim().toLowerCase();
    }

    /**
     * @description Whether the email belongs to a contact of a RutaCargo customer
     *              account or to an active OR inactive user of the profile
     *              "RutaCargo Customer".
     * @param normalizedEmail the normalized email
     * @return true when the email is registered
     */
    public static Boolean isEmailRegistered(String normalizedEmail) {
        if (String.isBlank(normalizedEmail)) {
            return false;
        }
        Integer contacts = [
            SELECT COUNT() FROM Contact
            WHERE Email = :normalizedEmail AND Account.Customer_Type__c != null
            WITH SYSTEM_MODE
        ];
        if (contacts > 0) {
            return true;
        }
        return [
            SELECT COUNT() FROM User
            WHERE Email = :normalizedEmail AND Profile.Name = :CUSTOMER_PROFILE_NAME
            WITH SYSTEM_MODE
        ] > 0;
    }

    /**
     * @description The username of the ACTIVE user of the profile "RutaCargo
     *              Customer" with the email. An internal user's email is never
     *              resolved.
     * @param normalizedEmail the normalized email
     * @return the username, or null when there is not exactly one such user
     */
    public static String activeCustomerUsername(String normalizedEmail) {
        if (String.isBlank(normalizedEmail) || normalizedEmail.length() > MAX_EMAIL_LENGTH) {
            return null;
        }
        List<User> customers = [
            SELECT Username FROM User
            WHERE Email = :normalizedEmail AND IsActive = true AND Profile.Name = :CUSTOMER_PROFILE_NAME
            WITH SYSTEM_MODE
            LIMIT 2
        ];
        return customers.size() == 1 ? customers[0].Username : null;
    }

    /**
     * @description Registers a customer: when the email is not registered and
     *              the password meets the profile's policy, inserts the Account
     *              and the Contact, creates the external user and enqueues the
     *              permission set assignment, all or nothing.
     * @param applicant the validated values (email normalized)
     * @param password the validated password
     * @return the outcome
     */
    public static Outcome register(Applicant applicant, String password) {
        if (isEmailRegistered(applicant.email)) {
            return Outcome.REGISTERED;
        }
        Id profileId = customerProfileId();
        if (profileId == null) {
            return Outcome.FAILED;
        }
        User newUser = buildUser(applicant, profileId);
        try {
            gateway.validatePassword(newUser, password);
        } catch (Exception policyFailure) {
            return Outcome.INVALID_PASSWORD;
        }
        return createCustomer(applicant, newUser, password);
    }

    private static Outcome createCustomer(Applicant applicant, User newUser, String password) {
        Savepoint beforeCustomer = Database.setSavepoint();
        try {
            Account customer = new Account(Name = applicant.accountName, Customer_Type__c = applicant.customerType);
            Database.insert(customer, AccessLevel.SYSTEM_MODE);
            Contact person = new Contact(
                FirstName = applicant.firstName,
                LastName = applicant.lastName,
                Email = applicant.email,
                Phone = applicant.phone,
                AccountId = customer.Id
            );
            Database.insert(person, AccessLevel.SYSTEM_MODE);
            newUser.ContactId = person.Id;
            Id userId = gateway.createExternalUser(newUser, customer.Id, password);
            if (userId == null) {
                throw new RegistrationException('No external user was created.');
            }
            System.enqueueJob(new CustomerPermissionAssigner(userId));
            return Outcome.CREATED;
        } catch (Exception creationFailure) {
            Database.rollback(beforeCustomer);
            return Outcome.FAILED;
        }
    }

    private static Id customerProfileId() {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :CUSTOMER_PROFILE_NAME WITH SYSTEM_MODE LIMIT 1];
        return profiles.isEmpty() ? null : profiles[0].Id;
    }

    private static User buildUser(Applicant applicant, Id profileId) {
        String localPart = applicant.email.substringBefore('@');
        return new User(
            FirstName = applicant.firstName,
            LastName = applicant.lastName,
            Email = applicant.email,
            Username = applicant.email + '.' + UserInfo.getOrganizationId().toLowerCase(),
            CommunityNickname = localPart.left(NICKNAME_PREFIX_LENGTH) + '-' + randomCharacters(NICKNAME_RANDOM_LENGTH),
            Alias = localPart.replaceAll('[^a-z]', '').left(ALIAS_LETTERS) + randomCharacters(ALIAS_RANDOM_LENGTH),
            ProfileId = profileId,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'es_MX',
            TimeZoneSidKey = 'America/Mexico_City',
            EmailEncodingKey = 'UTF-8'
        );
    }

    private static String randomCharacters(Integer length) {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(128)).left(length);
    }

    /** @description The real platform calls. */
    private inherited sharing class PlatformSiteGateway implements SiteGateway {
        /** @description Site.validatePassword with the password as its own confirmation (the controller compared them). */
        public void validatePassword(User newUser, String password) {
            Site.validatePassword(newUser, password, password);
        }

        /** @description Site.createExternalUser: creates the user for the account's contact (newUser.ContactId). */
        public Id createExternalUser(User newUser, Id accountId, String password) {
            return Site.createExternalUser(newUser, accountId, password);
        }
    }
}
