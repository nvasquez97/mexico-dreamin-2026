/**
 * Resolves the account of the logged-in site customer from the session
 * (never from the browser), for BR-07: each customer sees and manages only
 * their own shipments.
 */
public inherited sharing class CustomerContext {
    private CustomerContext() {}

    /**
     * @return the account id of the current site user
     * @throws AuraHandledException when the current user is not a site customer
     */
    public static Id getCurrentAccountId() {
        // System mode only to read the current user's own AccountId.
        List<User> users = [SELECT ContactId, Contact.AccountId FROM User WHERE Id = :UserInfo.getUserId() WITH SYSTEM_MODE LIMIT 1];
        Id accountId = (users.isEmpty() || users[0].ContactId == null) ? null : users[0].Contact.AccountId;
        if (accountId == null) {
            throw AuraErrors.of('Only registered customers can use this page.');
        }
        return accountId;
    }
}
