/**
 * Apex for the guest-facing sign-up / login / password-reset forms (REQ-005).
 * Kept apart from CustomerPortalController so the guest profile never gets access to customer data.
 */
public without sharing class AuthController {
    public static final String CUSTOMER_PROFILE = 'RutaCargo Customer';
    @TestVisible private static final String USERNAME_SUFFIX = '.rutacargo';
    private static final String BAD_LOGIN = 'Incorrect email or password.';

    public class SignupRequest {
        @AuraEnabled public String customerType;
        @AuraEnabled public String accountName;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String password;
    }

    /** Seam so unit tests can avoid Site.* calls, which only work inside a live site. */
    public interface UserCreator {
        Id createUser(User u, Id accountId, String password);
        String login(String username, String password, String startUrl);
        Boolean forgotPassword(String username);
    }

    public class SiteUserCreator implements UserCreator {
        public Id createUser(User u, Id accountId, String password) {
            return Site.createExternalUser(u, accountId, password, false);
        }
        public String login(String username, String password, String startUrl) {
            PageReference pr = Site.login(username, password, startUrl);
            return pr == null ? null : pr.getUrl();
        }
        public Boolean forgotPassword(String username) {
            return Site.forgotPassword(username);
        }
    }

    @TestVisible private static UserCreator creator = new SiteUserCreator();

    // AC-005.1 .. AC-005.4
    @AuraEnabled
    public static String signUp(Map<String, Object> form, String startUrl) {
        if (form == null) {
            throw ShipmentRules.userError('Complete the form.');
        }
        SignupRequest r = new SignupRequest();
        r.customerType = asText(form.get('customerType'));
        r.accountName = asText(form.get('accountName'));
        r.firstName = asText(form.get('firstName'));
        r.lastName = asText(form.get('lastName'));
        r.email = asText(form.get('email'));
        r.phone = asText(form.get('phone'));
        r.password = asText(form.get('password'));
        String email = clean(r.email).toLowerCase();
        if (r.customerType != 'Individual' && r.customerType != 'Business') {
            throw ShipmentRules.userError('Choose whether you are an individual or a business.');
        }
        if (String.isBlank(r.accountName) || String.isBlank(r.firstName) || String.isBlank(r.lastName)
            || String.isBlank(r.phone)) {
            throw ShipmentRules.userError('Complete all the fields.');
        }
        if (!ShipmentRules.isEmail(email)) {
            throw ShipmentRules.userError('Enter a valid email address.');
        }
        if (!ShipmentRules.isValidPassword(r.password)) {
            throw ShipmentRules.userError('The password must have at least 10 characters, with letters and numbers.');
        }
        String username = email + USERNAME_SUFFIX;
        if (username.length() > 80) {
            throw ShipmentRules.userError('That email address is too long.');
        }
        // AC-005.3: one account per email
        if (![SELECT Id FROM User WHERE Email = :email OR Username = :username WITH SYSTEM_MODE LIMIT 1].isEmpty()) {
            throw ShipmentRules.userError('This email is already registered. Please log in.');
        }

        Account acc = new Account(Name = clean(r.accountName), Customer_Type__c = r.customerType, Phone = clean(r.phone));
        Database.insert(acc, AccessLevel.SYSTEM_MODE);

        User u = new User(
            FirstName = clean(r.firstName),
            LastName = clean(r.lastName),
            Email = email,
            Username = username,
            Phone = clean(r.phone),
            Alias = (clean(r.firstName).left(1) + clean(r.lastName)).left(8),
            CommunityNickname = (email.substringBefore('@') + String.valueOf(Math.abs(Crypto.getRandomInteger()))).left(40),
            ProfileId = customerProfileId(),
            TimeZoneSidKey = ShipmentRules.MEXICO_TZ,
            LocaleSidKey = 'es_MX',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey = 'UTF-8'
        );
        try {
            creator.createUser(u, acc.Id, r.password);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Sign-up failed: ' + e.getTypeName() + ' ' + e.getMessage());
            throw ShipmentRules.userError('We could not create your account. Check your data and try again.');
        }
        return creator.login(username, r.password, safeStartUrl(startUrl));
    }

    // AC-005.5
    @AuraEnabled
    public static String login(String email, String password, String startUrl) {
        String username = usernameFor(email);
        String url;
        try {
            url = creator.login(username, password == null ? '' : password, safeStartUrl(startUrl));
        } catch (Exception e) {
            url = null;
        }
        if (url == null) {
            throw ShipmentRules.userError(BAD_LOGIN);
        }
        return url;
    }

    // AC-005.6: always the same answer, so the form cannot be used to discover registered emails
    @AuraEnabled
    public static void forgotPassword(String email) {
        if (!ShipmentRules.isEmail(email)) {
            throw ShipmentRules.userError('Enter a valid email address.');
        }
        try {
            creator.forgotPassword(usernameFor(email));
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'forgotPassword: ' + e.getMessage());
        }
    }

    private static String usernameFor(String email) {
        String e = clean(email).toLowerCase();
        List<User> users = [SELECT Username FROM User WHERE Email = :e AND IsActive = TRUE AND Profile.Name = :CUSTOMER_PROFILE WITH SYSTEM_MODE LIMIT 1];
        return users.isEmpty() ? e + USERNAME_SUFFIX : users[0].Username;
    }

    private static Id customerProfileId() {
        List<Profile> p = [SELECT Id FROM Profile WHERE Name = :CUSTOMER_PROFILE WITH SYSTEM_MODE LIMIT 1];
        if (p.isEmpty()) {
            throw ShipmentRules.userError('Sign-up is not available right now.');
        }
        return p[0].Id;
    }

    /** Only site-relative paths: no open redirects. */
    @TestVisible
    private static String safeStartUrl(String startUrl) {
        if (String.isNotBlank(startUrl) && startUrl.startsWith('/') && !startUrl.startsWith('//') && !startUrl.contains('\\')) {
            return startUrl;
        }
        return '/';
    }

    private static String asText(Object v) {
        return v == null ? null : String.valueOf(v);
    }

    private static String clean(String v) {
        return v == null ? '' : v.trim();
    }
}
