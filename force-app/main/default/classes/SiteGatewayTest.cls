/**
 * Tests for SiteGateway outside a site request, where the platform refuses
 * to log in or create users. Covers AC-005.5 (failed login is reported as an
 * error, never as success) and AC-005.2 (a failed user creation is an error).
 */
@IsTest
private class SiteGatewayTest {

    // Covers AC-005.5: when the platform does not log the user in, the gateway raises an error.
    @IsTest
    static void shouldRaiseError_WhenLoginNotPossible() {
        try {
            new SiteGateway().login('nobody@example.com.rutacargo', 'Cargo2026xyz', '/my-shipments');
            Assert.fail('Expected SiteGatewayException');
        } catch (SiteGateway.SiteGatewayException e) {
            Assert.isTrue(e.getMessage().startsWith('Site.login'), 'Login failure reported: ' + e.getMessage());
        }
    }

    // Covers AC-005.2: when the platform cannot create the site user, the gateway raises an error.
    @IsTest
    static void shouldRaiseError_WhenUserCannotBeCreated() {
        User newUser = new User(Username = 'nobody@example.com.rutacargo', Email = 'nobody@example.com', LastName = 'Nobody');
        try {
            new SiteGateway().createExternalUser(newUser, null, 'Cargo2026xyz');
            Assert.fail('Expected an exception');
        } catch (Exception e) {
            Assert.isNotNull(e.getMessage(), 'Creation failure reported');
        }
    }

    // Covers AC-005.6: outside a site the reset request reports false and does not throw.
    @IsTest
    static void shouldReturnFalse_WhenResetNotPossible() {
        Assert.isFalse(new SiteGateway().forgotPassword('nobody@example.com.rutacargo'), 'No reset outside a site');
    }
}
