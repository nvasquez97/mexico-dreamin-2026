/**
 * Customer sign-up, login and password reset for the site (REQ-005).
 *
 * WITHOUT SHARING and SYSTEM MODE on purpose: the caller is the site guest
 * user, who has no object permissions, and sign-up must create an account and
 * a contact and check that the email is not registered yet (AC-005.3).
 * Inputs are individual fields validated here; the response never returns
 * records, only a status, a user-facing message and a redirect URL.
 *
 * The site username is the email plus USERNAME_SUFFIX (usernames are global
 * across all Salesforce orgs); customers always type only their email.
 */
public without sharing class CustomerAuthController {
    public static final String USERNAME_SUFFIX = '.rutacargo';
    public static final String HOME_AFTER_LOGIN = '/my-shipments';
    public static final String CUSTOMER_PROFILE = 'RutaCargo Customer';
    private static final Set<String> CUSTOMER_TYPES = new Set<String>{ 'Individual', 'Business' };
    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[a-z0-9._%+\\-]+@[a-z0-9.\\-]+\\.[a-z]{2,}$');
    private static final Pattern PHONE_PATTERN = Pattern.compile('^\\+?[0-9 ()\\-]{7,20}$');
    private static final Pattern LETTER = Pattern.compile('[A-Za-z]');
    private static final Pattern DIGIT = Pattern.compile('[0-9]');
    private static final String GENERIC_SIGNUP_ERROR = 'We could not create your account. Please check your data and try again.';

    @TestVisible
    private static SiteGateway gateway = new SiteGateway();

    /** Result of every auth operation. */
    public class AuthResult {
        @AuraEnabled public Boolean success = false;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean emailAlreadyRegistered = false;
        @AuraEnabled public String redirectUrl;
    }

    private class ValidationException extends Exception {}

    /**
     * Creates the customer: an account, its contact and the site user, then logs in (AC-005.1, AC-005.2).
     * @return success with the login redirect, or a user-facing message
     */
    @AuraEnabled
    public static AuthResult register(
        String customerType, String accountName, String firstName, String lastName,
        String email, String phone, String password
    ) {
        AuthResult result = new AuthResult();
        String normalizedEmail = normalizeEmail(email);
        try {
            validateSignUp(customerType, accountName, firstName, lastName, normalizedEmail, phone, password);
        } catch (ValidationException e) {
            result.message = e.getMessage();
            return result;
        }
        if (isEmailRegistered(normalizedEmail)) {
            result.emailAlreadyRegistered = true;
            result.message = 'This email is already registered. Log in instead.';
            return result;
        }
        Savepoint beforeSignUp = Database.setSavepoint();
        Id userId;
        try {
            userId = createCustomer(customerType, accountName.trim(), firstName.trim(), lastName.trim(), normalizedEmail, phone.trim(), password);
        } catch (Exception e) {
            // Platform or DML failure: undo the account and contact, show a generic message.
            Database.rollback(beforeSignUp);
            result.message = GENERIC_SIGNUP_ERROR;
            return result;
        }
        System.enqueueJob(new CustomerAccessQueueable(userId));
        result.success = true;
        try {
            result.redirectUrl = gateway.login(toUsername(normalizedEmail), password, HOME_AFTER_LOGIN);
        } catch (SiteGateway.SiteGatewayException e) {
            result.message = 'Your account was created. Please log in.';
        }
        return result;
    }

    /**
     * Logs a customer in with email and password (AC-005.5).
     * @return success with the redirect URL, or a generic message
     */
    @AuraEnabled
    public static AuthResult login(String email, String password) {
        AuthResult result = new AuthResult();
        String normalizedEmail = normalizeEmail(email);
        if (!EMAIL_PATTERN.matcher(normalizedEmail).matches() || String.isBlank(password)) {
            result.message = 'Invalid email or password.';
            return result;
        }
        try {
            result.redirectUrl = gateway.login(toUsername(normalizedEmail), password, HOME_AFTER_LOGIN);
            result.success = true;
        } catch (SiteGateway.SiteGatewayException e) {
            result.message = 'Invalid email or password.';
        }
        return result;
    }

    /**
     * Sends the reset link by email (AC-005.6). The answer never reveals whether the email is registered.
     * @return always success with a neutral message
     */
    @AuraEnabled
    public static AuthResult forgotPassword(String email) {
        AuthResult result = new AuthResult();
        String normalizedEmail = normalizeEmail(email);
        if (EMAIL_PATTERN.matcher(normalizedEmail).matches()) {
            gateway.forgotPassword(toUsername(normalizedEmail));
        }
        result.success = true;
        result.message = 'If the email is registered, you will receive a link to reset your password.';
        return result;
    }

    private static String normalizeEmail(String email) {
        return (email ?? '').trim().toLowerCase();
    }

    @TestVisible
    private static String toUsername(String normalizedEmail) {
        return normalizedEmail + USERNAME_SUFFIX;
    }

    private static void validateSignUp(
        String customerType, String accountName, String firstName, String lastName,
        String email, String phone, String password
    ) {
        if (!CUSTOMER_TYPES.contains(customerType)) {
            throw new ValidationException('Choose a customer type: Individual or Business.');
        }
        if (String.isBlank(accountName) || accountName.trim().length() > 255) {
            throw new ValidationException('Enter your name or legal name (up to 255 characters).');
        }
        if (String.isBlank(firstName) || String.isBlank(lastName) || firstName.trim().length() > 40 || lastName.trim().length() > 80) {
            throw new ValidationException('Enter the first and last name of the contact person.');
        }
        if (!EMAIL_PATTERN.matcher(email).matches() || email.length() > 70) {
            throw new ValidationException('Enter a valid email.');
        }
        if (String.isBlank(phone) || !PHONE_PATTERN.matcher(phone.trim()).matches()) {
            throw new ValidationException('Enter a valid phone number.');
        }
        if (!isStrongPassword(password)) {
            throw new ValidationException('The password must have at least 10 characters, with letters and numbers.');
        }
    }

    /** AC-005.4: at least 10 characters, with letters and numbers. */
    @TestVisible
    private static Boolean isStrongPassword(String password) {
        return password != null && password.length() >= 10 &&
            LETTER.matcher(password).find() && DIGIT.matcher(password).find();
    }

    /** AC-005.3: one account per email (site user or customer contact). System mode: see class comment. */
    private static Boolean isEmailRegistered(String email) {
        String username = toUsername(email);
        Integer users = [SELECT COUNT() FROM User WHERE Username = :username WITH SYSTEM_MODE];
        Integer contacts = [
            SELECT COUNT() FROM Contact
            WHERE Email = :email AND Account.Customer_Type__c != null
            WITH SYSTEM_MODE
        ];
        return users + contacts > 0;
    }

    private static Id createCustomer(
        String customerType, String accountName, String firstName, String lastName,
        String email, String phone, String password
    ) {
        Id ownerId = RutaCargo_Settings__c.getOrgDefaults()?.Account_Owner_Id__c;
        if (ownerId == null) {
            throw new SiteGateway.SiteGatewayException('RutaCargo_Settings__c.Account_Owner_Id__c is not set');
        }
        // System mode: the guest has no object permissions (see class comment).
        Account customer = new Account(Name = accountName, Customer_Type__c = customerType, Phone = phone, OwnerId = ownerId);
        Database.insert(customer, AccessLevel.SYSTEM_MODE);
        Contact person = new Contact(
            AccountId = customer.Id, FirstName = firstName, LastName = lastName,
            Email = email, Phone = phone, OwnerId = ownerId
        );
        Database.insert(person, AccessLevel.SYSTEM_MODE);
        User siteUser = new User(
            ContactId = person.Id,
            Username = toUsername(email),
            Email = email,
            FirstName = firstName,
            LastName = lastName,
            Alias = (firstName.left(1) + lastName).replaceAll('[^A-Za-z0-9]', '').left(8),
            CommunityNickname = (email.substringBefore('@').left(30) + String.valueOf(Crypto.getRandomInteger()).right(6)),
            TimeZoneSidKey = BusinessCalendar.MEXICO_CITY_TIME_ZONE,
            LocaleSidKey = 'en_US',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8'
        );
        return gateway.createExternalUser(siteUser, customer.Id, password);
    }
}
