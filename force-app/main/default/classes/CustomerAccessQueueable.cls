/**
 * Gives a newly registered site customer the RutaCargo_Customer permission
 * set (AC-005.2). Runs asynchronously because a permission set assignment is
 * a setup object and cannot be inserted in the same transaction as the
 * account and contact created at sign-up (mixed DML).
 *
 * WITHOUT SHARING and SYSTEM MODE: it is enqueued by the site guest user.
 * It only acts on active users of the RutaCargo Customer profile (BR-07).
 */
public without sharing class CustomerAccessQueueable implements Queueable {
    public static final String CUSTOMER_PERMISSION_SET = 'RutaCargo_Customer';
    private final Id userId;

    /**
     * @param userId the new site user
     */
    public CustomerAccessQueueable(Id userId) {
        this.userId = userId;
    }

    /** Assigns the permission set once; does nothing for any other kind of user. */
    public void execute(QueueableContext context) {
        List<User> customers = [
            SELECT Id FROM User
            WHERE Id = :userId AND IsActive = true AND ContactId != null
                AND Profile.Name = :CustomerAuthController.CUSTOMER_PROFILE
            WITH SYSTEM_MODE
        ];
        if (customers.isEmpty()) {
            return;
        }
        Integer existing = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.Name = :CUSTOMER_PERMISSION_SET
            WITH SYSTEM_MODE
        ];
        if (existing > 0) {
            return;
        }
        PermissionSet customerAccess = [SELECT Id FROM PermissionSet WHERE Name = :CUSTOMER_PERMISSION_SET WITH SYSTEM_MODE LIMIT 1];
        Database.insert(
            new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = customerAccess.Id),
            AccessLevel.SYSTEM_MODE
        );
    }
}
