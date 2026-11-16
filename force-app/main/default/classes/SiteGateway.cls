/**
 * Thin wrapper over the Site methods used by sign-up and login, so the
 * controller can be tested: Site.createExternalUser, Site.login and
 * Site.forgotPassword only work inside a real site request.
 */
public virtual inherited sharing class SiteGateway {
    /** Any platform failure. Its message is internal; never show it on the site. */
    public class SiteGatewayException extends Exception {}

    /**
     * Creates the site user for an existing account and contact.
     * @return the new user id
     */
    public virtual Id createExternalUser(User newUser, Id accountId, String password) {
        try {
            Id userId = Site.createExternalUser(newUser, accountId, password, false);
            if (userId == null) {
                throw new SiteGatewayException('Site.createExternalUser returned no user');
            }
            return userId;
        } catch (Site.ExternalUserCreateException e) {
            throw new SiteGatewayException('Site.createExternalUser failed', e);
        }
    }

    /**
     * Logs the user in.
     * @return the URL the browser must open to finish the login
     */
    public virtual String login(String username, String password, String startUrl) {
        PageReference page;
        try {
            page = Site.login(username, password, startUrl);
        } catch (Exception e) {
            throw new SiteGatewayException('Site.login failed', e);
        }
        if (page == null) {
            throw new SiteGatewayException('Site.login returned no page');
        }
        return page.getUrl();
    }

    /**
     * Sends the reset-password email of the site to the user, if it exists.
     * @return what the platform answered (not shown to the visitor)
     */
    public virtual Boolean forgotPassword(String username) {
        return Site.forgotPassword(username);
    }
}
