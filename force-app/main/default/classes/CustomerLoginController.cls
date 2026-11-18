/**
 * @description Guest-callable customer login and password reset of the RutaCargo
 *              site (odd/tasks/req-005-customer-signup.md S3, AC-005.5, AC-005.6).
 *              Customers type their email; CustomerRegistration maps it to the
 *              username of an ACTIVE user of the profile "RutaCargo Customer"
 *              (an internal user's email is never resolved). An unknown email,
 *              an internal user and a wrong password get the same message; the
 *              reset always returns the same result. The startUrl is accepted
 *              only from a closed list of site-relative pages, else "/".
 *              Login lockout is the profile's password policy (S1, F4).
 */
public with sharing class CustomerLoginController {

    public static final String LOGIN_FAILED_MESSAGE = 'Your email or password is incorrect.';
    public static final String DEFAULT_START_URL = '/';
    // REQ-006/007 pages, listed before they exist (F6): until then they resolve to the site's 404.
    private static final Set<String> START_URLS = new Set<String>{ '/', '/my-shipments', '/request-shipment' };

    /**
     * @description The platform calls of login and reset. Tests replace it
     *              (@TestVisible seam): Site.login and Site.forgotPassword need a
     *              live site session.
     */
    public interface SiteAuthGateway {
        /**
         * @description Logs the user in.
         * @param username the customer's username
         * @param password the password
         * @param startUrl the site-relative page after login
         * @return the redirect URL, or null when the login failed
         */
        String login(String username, String password, String startUrl);

        /**
         * @description Sends the platform's password reset email.
         * @param username the customer's username
         * @return whether the platform accepted the request
         */
        Boolean forgotPassword(String username);
    }

    @TestVisible
    private static SiteAuthGateway gateway = new PlatformSiteAuthGateway();

    /** @description The answer of a login. */
    public class LoginResult {
        /** @description True when the platform logged the customer in. */
        @AuraEnabled public Boolean success;
        /** @description The URL to open after a successful login, or null. */
        @AuraEnabled public String redirectUrl;
        /** @description The one failure message, or null. */
        @AuraEnabled public String message;
    }

    /**
     * @description Logs a customer in with email and password.
     * @param email the email (any case, trimmed on the server)
     * @param password the password
     * @param startUrl the requested page; only "/", "/my-shipments" and
     *        "/request-shipment" are kept, anything else becomes "/"
     * @return the redirect URL, or the one failure message
     */
    @AuraEnabled
    public static LoginResult login(String email, String password, String startUrl) {
        String username = CustomerRegistration.activeCustomerUsername(CustomerRegistration.normalizeEmail(email));
        if (username == null || String.isBlank(password)) {
            return loginResult(null);
        }
        String redirectUrl;
        try {
            redirectUrl = gateway.login(username, password, safeStartUrl(startUrl));
        } catch (Exception loginFailure) {
            // A wrong password or a locked user: the same answer as an unknown email.
            redirectUrl = null;
        }
        return loginResult(redirectUrl);
    }

    /**
     * @description Requests a password reset email. The platform sends it only
     *              to a registered customer; every email gets the same result.
     * @param email the email (any case, trimmed on the server)
     * @return always true
     */
    @AuraEnabled
    public static Boolean forgotPassword(String email) {
        String username = CustomerRegistration.activeCustomerUsername(CustomerRegistration.normalizeEmail(email));
        if (username != null) {
            requestReset(username);
        }
        return true;
    }

    private static void requestReset(String username) {
        try {
            gateway.forgotPassword(username);
        } catch (Exception resetFailure) {
            // The visitor gets the same answer whether or not the platform sent the email.
            return;
        }
    }

    private static String safeStartUrl(String startUrl) {
        return START_URLS.contains(startUrl) ? startUrl : DEFAULT_START_URL;
    }

    private static LoginResult loginResult(String redirectUrl) {
        LoginResult answer = new LoginResult();
        answer.success = String.isNotBlank(redirectUrl);
        answer.redirectUrl = answer.success ? redirectUrl : null;
        answer.message = answer.success ? null : LOGIN_FAILED_MESSAGE;
        return answer;
    }

    /** @description The real platform calls. */
    private inherited sharing class PlatformSiteAuthGateway implements SiteAuthGateway {
        /** @description Site.login: the redirect URL, or null. */
        public String login(String username, String password, String startUrl) {
            PageReference target = Site.login(username, password, startUrl);
            return target?.getUrl();
        }

        /** @description Site.forgotPassword: the platform sends the reset email. */
        public Boolean forgotPassword(String username) {
            return Site.forgotPassword(username);
        }
    }
}
