/**
 * @description Tests of the customer login and password reset
 *              (odd/tasks/req-005-customer-signup.md S3): CustomerLoginController
 *              and the CustomerRegistration lookup behind it. AC-005.5 (server),
 *              AC-005.6 (server) and AC-005.7 (the real site guest runs both).
 *              Site.login and Site.forgotPassword run through the
 *              CustomerLoginController.gateway seam; the customer is the seeded user
 *              Ana López (tests never insert portal users, F7).
 */
@IsTest
private with sharing class CustomerLoginControllerTest {

    private static final String RIGHT_PASS = 'abcd12345X';
    private static final String WRONG_PASS = 'abcd12345Y';
    private static final String REDIRECT_BASE = '/rutacargo/secur/frontdoor.jsp?startURL=';

    /** @description The seam: a fake platform that knows one right password. */
    private inherited sharing class FakeSite implements CustomerLoginController.SiteAuthGateway {
        List<String> loginUsernames = new List<String>();
        List<String> loginStartUrls = new List<String>();
        List<String> resetUsernames = new List<String>();
        Boolean failReset = false;

        public String login(String username, String pass, String startUrl) {
            loginUsernames.add(username);
            loginStartUrls.add(startUrl);
            if (pass != null && pass.equals(RIGHT_PASS)) {
                return REDIRECT_BASE + EncodingUtil.urlEncode(startUrl, 'UTF-8');
            }
            throw new CustomerRegistration.RegistrationException('Simulated wrong password.');
        }

        public Boolean forgotPassword(String username) {
            resetUsernames.add(username);
            if (failReset) {
                throw new CustomerRegistration.RegistrationException('Simulated reset failure.');
            }
            return true;
        }
    }

    private static FakeSite installFakeSite() {
        FakeSite fake = new FakeSite();
        CustomerLoginController.gateway = fake;
        return fake;
    }

    private static CustomerLoginController.LoginResult loginAsGuest(String email, String pass, String startUrl) {
        CustomerLoginController.LoginResult result;
        System.runAs(TestDataFactory.siteGuestUser()) {
            result = CustomerLoginController.login(email, pass, startUrl);
        }
        return result;
    }

    private static Boolean forgotAsGuest(String email) {
        Boolean result;
        System.runAs(TestDataFactory.siteGuestUser()) {
            result = CustomerLoginController.forgotPassword(email);
        }
        return result;
    }

    private static String anaUsername() {
        return TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL).Username;
    }

    private static String martaUsername() {
        return TestDataFactory.seededCustomerUser(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL).Username;
    }

    /** @description Logs in as the guest with the right password and returns the startUrl the platform got. */
    private static String listedStartUrlPassedFor(String startUrl) {
        FakeSite fake = installFakeSite();
        CustomerLoginController.LoginResult result = loginAsGuest(TestDataFactory.SEEDED_CUSTOMER_EMAIL, RIGHT_PASS, startUrl);
        Assert.isTrue(result.success, 'The login succeeds: ' + result.message);
        Assert.areEqual(1, fake.loginStartUrls.size(), 'Site.login is called once');
        return fake.loginStartUrls[0];
    }

    private static void assertLoginFailed(CustomerLoginController.LoginResult result) {
        Assert.isFalse(result.success, 'The login must fail');
        Assert.isNull(result.redirectUrl, 'No redirect URL on a failure');
        Assert.areEqual('Your email or password is incorrect.', result.message, 'The one login failure message');
    }

    /** @description Logs in as the guest with the right password and returns the startUrl the platform got. */
    private static String startUrlPassedFor(String startUrl) {
        FakeSite fake = installFakeSite();
        CustomerLoginController.LoginResult result = loginAsGuest(TestDataFactory.SEEDED_CUSTOMER_EMAIL, RIGHT_PASS, startUrl);
        Assert.isTrue(result.success, 'The login succeeds');
        Assert.areEqual(REDIRECT_BASE + EncodingUtil.urlEncode('/', 'UTF-8'), result.redirectUrl, 'Redirect to the site home');
        return fake.loginStartUrls[0];
    }

    // ─── AC-005.5: login ──────────────────────────────────────────────────

    @IsTest
    static void login_upperCaseEmailAndRightPassword_returnsRedirectForListedStartUrl() {
        // AC-005.5: email in any case, startUrl from the closed list
        FakeSite fake = installFakeSite();
        CustomerLoginController.LoginResult result = loginAsGuest('ANA.LOPEZ@EXAMPLE.COM', RIGHT_PASS, '/my-shipments');
        Assert.isTrue(result.success, 'The login succeeds: ' + result.message);
        Assert.areEqual(REDIRECT_BASE + EncodingUtil.urlEncode('/my-shipments', 'UTF-8'), result.redirectUrl, 'The platform redirect URL');
        Assert.isNull(result.message, 'No failure message on a successful login');
        Assert.areEqual(anaUsername(), fake.loginUsernames[0], 'Site.login gets the customer username');
        Assert.areEqual('/my-shipments', fake.loginStartUrls[0], 'The listed startUrl is passed');
    }

    @IsTest
    static void login_trimmedMixedCaseEmail_passesOtherListedStartUrl() {
        // AC-005.5: second input, the other listed page
        FakeSite fake = installFakeSite();
        CustomerLoginController.LoginResult result = loginAsGuest(' Ana.Lopez@Example.com ', RIGHT_PASS, '/request-shipment');
        Assert.isTrue(result.success, 'The login succeeds: ' + result.message);
        Assert.areEqual(REDIRECT_BASE + EncodingUtil.urlEncode('/request-shipment', 'UTF-8'), result.redirectUrl, 'The platform redirect URL');
        Assert.isNull(result.message, 'No failure message on a successful login');
        Assert.areEqual('/request-shipment', fake.loginStartUrls[0], 'The listed startUrl is passed');
    }

    @IsTest
    static void login_basePathPrefixedShipmentsStartUrl_passesTheListedPage() {
        // AC-005.5 (F13): the site base path form of a listed page (/rutacargo/my-shipments) is the same page
        Assert.areEqual('/my-shipments', listedStartUrlPassedFor('/rutacargo/my-shipments'), 'The prefixed form maps to the listed page');
    }

    @IsTest
    static void login_basePathPrefixedRequestStartUrl_passesTheListedPage() {
        // AC-005.5 (F13): a second prefixed page (/rutacargo/request-shipment)
        Assert.areEqual('/request-shipment', listedStartUrlPassedFor('/rutacargo/request-shipment'), 'The prefixed form maps to the listed page');
    }

    @IsTest
    static void login_basePathHomeStartUrl_passesTheSiteHome() {
        // AC-005.5 (F13): the site base path itself (/rutacargo/) is the site home
        Assert.areEqual('/', listedStartUrlPassedFor('/rutacargo/'), 'The prefixed home maps to "/"');
    }

    @IsTest
    static void login_otherPrefixStartUrl_becomesSiteHome() {
        // AC-005.5: a look-alike prefix (/rutacargox/my-shipments) is outside the list
        Assert.areEqual('/', startUrlPassedFor('/rutacargox/my-shipments'), 'Only the site base path is accepted as a prefix');
    }

    @IsTest
    static void login_prefixedUnlistedPathStartUrl_becomesSiteHome() {
        // AC-005.5: the prefix does not open pages outside the list (/rutacargo/secur/frontdoor.jsp)
        Assert.areEqual('/', startUrlPassedFor('/rutacargo/secur/frontdoor.jsp'), 'A prefixed path outside the list is replaced');
    }

    @IsTest
    static void login_absoluteExternalStartUrl_becomesSiteHome() {
        // AC-005.5: https://evil.example → "/"
        Assert.areEqual('/', startUrlPassedFor('https://evil.example'), 'An absolute URL is replaced');
    }

    @IsTest
    static void login_protocolRelativeStartUrl_becomesSiteHome() {
        // AC-005.5: //evil.example → "/"
        Assert.areEqual('/', startUrlPassedFor('//evil.example'), 'A protocol-relative URL is replaced');
    }

    @IsTest
    static void login_unlistedSitePathStartUrl_becomesSiteHome() {
        // AC-005.5: /secur/frontdoor.jsp → "/"
        Assert.areEqual('/', startUrlPassedFor('/secur/frontdoor.jsp'), 'A path outside the list is replaced');
    }

    @IsTest
    static void login_nullStartUrl_becomesSiteHome() {
        // AC-005.5: no startUrl → "/"
        Assert.areEqual('/', startUrlPassedFor(null), 'No startUrl means the site home');
    }

    @IsTest
    static void login_unknownEmail_failsWithoutCallingSiteLogin() {
        // AC-005.5: unknown email → the same message
        FakeSite fake = installFakeSite();
        assertLoginFailed(loginAsGuest('nobody.here@example.com', RIGHT_PASS, '/'));
        Assert.areEqual(0, fake.loginUsernames.size(), 'Site.login is not called');
    }

    @IsTest
    static void login_internalUserEmail_failsWithoutCallingSiteLogin() {
        // AC-005.5: an internal user's email (the running admin's) is never resolved
        String adminEmail = UserInfo.getUserEmail();
        FakeSite fake = installFakeSite();
        assertLoginFailed(loginAsGuest(adminEmail, RIGHT_PASS, '/'));
        Assert.areEqual(0, fake.loginUsernames.size(), 'Site.login is never called for an internal user');
    }

    @IsTest
    static void login_emptyPassword_failsWithoutCallingSiteLogin() {
        // AC-005.5: an empty password never reaches the platform
        FakeSite fake = installFakeSite();
        assertLoginFailed(loginAsGuest(TestDataFactory.SEEDED_CUSTOMER_EMAIL, '', '/'));
        Assert.areEqual(0, fake.loginUsernames.size(), 'Site.login is not called for an empty password');
    }

    @IsTest
    static void login_passwordOfSpaces_failsWithoutCallingSiteLogin() {
        // AC-005.5: a password of only spaces is blank (second input)
        FakeSite fake = installFakeSite();
        assertLoginFailed(loginAsGuest(TestDataFactory.SEEDED_CUSTOMER_EMAIL, '   ', '/'));
        Assert.areEqual(0, fake.loginUsernames.size(), 'Site.login is not called for a blank password');
    }

    @IsTest
    static void login_wrongPassword_failsWithTheSameMessage() {
        // AC-005.5: wrong password → the same message
        FakeSite fake = installFakeSite();
        assertLoginFailed(loginAsGuest(TestDataFactory.SEEDED_CUSTOMER_EMAIL, WRONG_PASS, '/'));
        Assert.areEqual(1, fake.loginUsernames.size(), 'The platform checked the password');
    }

    @IsTest
    static void login_inactiveCustomer_failsWithoutCallingSiteLogin() {
        // AC-005.5: only an ACTIVE customer user is resolved
        User marta = TestDataFactory.seededCustomerUser(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL);
        TestDataFactory.deactivateUser(marta.Id);
        FakeSite fake = installFakeSite();
        assertLoginFailed(loginAsGuest(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL, RIGHT_PASS, '/'));
        Assert.areEqual(0, fake.loginUsernames.size(), 'Site.login is not called');
    }

    @IsTest
    static void login_asAdmin_returnsRedirect() {
        // AC-005.5: the same server path for an internal caller
        installFakeSite();
        CustomerLoginController.LoginResult result = CustomerLoginController.login(TestDataFactory.SEEDED_CUSTOMER_EMAIL, RIGHT_PASS, '/');
        Assert.isTrue(result.success, 'The login succeeds');
        Assert.areEqual(REDIRECT_BASE + EncodingUtil.urlEncode('/', 'UTF-8'), result.redirectUrl, 'Redirect URL');
    }

    // ─── AC-005.6: password reset ─────────────────────────────────────────

    @IsTest
    static void forgotPassword_registeredCustomer_resetsItsUsername() {
        // AC-005.6: the reset is called for the registered customer, with its username
        FakeSite fake = installFakeSite();
        Assert.isTrue(forgotAsGuest(' Ana.Lopez@Example.com '), 'The same result for every email');
        Assert.areEqual(new List<String>{ anaUsername() }, fake.resetUsernames, 'Site.forgotPassword gets the username once');
    }

    @IsTest
    static void forgotPassword_secondRegisteredCustomer_resetsHerUsername() {
        // AC-005.6: a second registered customer (Marta), any case, gets the reset with her own username
        FakeSite fake = installFakeSite();
        Assert.isTrue(forgotAsGuest(' MARTA.Ruiz@Example.COM '), 'The same result for every email');
        Assert.areEqual(new List<String>{ martaUsername() }, fake.resetUsernames, 'Site.forgotPassword gets Marta\'s username once');
        Assert.areNotEqual(anaUsername(), fake.resetUsernames[0], 'Not another customer\'s username');
    }

    @IsTest
    static void forgotPassword_unregisteredEmail_returnsSameResultWithoutReset() {
        // AC-005.6: an unregistered email
        FakeSite fake = installFakeSite();
        Assert.isTrue(forgotAsGuest('nobody.here@example.com'), 'The same result for every email');
        Assert.areEqual(0, fake.resetUsernames.size(), 'Site.forgotPassword is not called');
    }

    @IsTest
    static void forgotPassword_internalUserEmail_returnsSameResultWithoutReset() {
        // AC-005.6: an internal user's email never gets a reset
        String adminEmail = UserInfo.getUserEmail();
        FakeSite fake = installFakeSite();
        Assert.isTrue(forgotAsGuest(adminEmail), 'The same result for every email');
        Assert.areEqual(0, fake.resetUsernames.size(), 'Site.forgotPassword is never called for an internal user');
    }

    @IsTest
    static void forgotPassword_platformFails_returnsSameResult() {
        // AC-005.6: a platform failure does not change the answer
        FakeSite fake = installFakeSite();
        fake.failReset = true;
        Assert.isTrue(forgotAsGuest(TestDataFactory.SEEDED_CUSTOMER_EMAIL), 'The same result for every email');
        Assert.areEqual(1, fake.resetUsernames.size(), 'The reset was attempted');
    }

    @IsTest
    static void forgotPassword_blankEmail_returnsSameResultWithoutReset() {
        // AC-005.6: an empty email
        FakeSite fake = installFakeSite();
        Assert.isTrue(forgotAsGuest('  '), 'The same result for every email');
        Assert.areEqual(0, fake.resetUsernames.size(), 'Site.forgotPassword is not called');
    }
}
