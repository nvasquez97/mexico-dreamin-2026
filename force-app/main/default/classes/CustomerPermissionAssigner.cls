/**
 * @description Assigns the permission set RutaCargo_Customer to a customer user
 *              created by the sign-up (odd/tasks/req-005-customer-signup.md S2).
 *              It runs as a Queueable because a PermissionSetAssignment in the
 *              sign-up transaction would be a mixed DML after the Account and
 *              Contact inserts. Only CustomerRegistration enqueues it, with the
 *              Id Site.createExternalUser returned (never a client value); it
 *              assigns only to a user of the profile "RutaCargo Customer" and
 *              only once.
 */
// SECURITY-JUSTIFICATION: the job runs as the user who signed up (the site guest),
// who cannot see other users under sharing, so the check that the new user has
// the profile "RutaCargo Customer" found no row with sharing (test
// signUp_enqueuesAssignerThatAssignsCustomerPermissionSet). Scope: this job only;
// one user Id that Site.createExternalUser returned to CustomerRegistration (never
// a client value); it reads one User, one PermissionSet and that user's
// assignments, and inserts at most one PermissionSetAssignment. Compensating
// control: it assigns only the constant permission set RutaCargo_Customer, only to
// a user of the profile "RutaCargo Customer", only once; the guest has no class
// access to it (customer-access-check.sh). (pending owner approval, 2026-11-17)
public without sharing class CustomerPermissionAssigner implements Queueable {

    /** @description The single actor permission set of registered customers. */
    public static final String PERMISSION_SET_NAME = 'RutaCargo_Customer';

    private final Id userId;

    /**
     * @description Keeps the new user's Id for the job.
     * @param userId the new customer user
     */
    public CustomerPermissionAssigner(Id userId) {
        this.userId = userId;
    }

    /**
     * @description Inserts the assignment when the user is a RutaCargo customer
     *              and does not have the permission set yet. System mode: the
     *              job runs as the user who signed up (the site guest), who has
     *              no permission on users or permission sets.
     * @param context the Queueable context
     */
    public void execute(QueueableContext context) {
        if (userId == null) {
            return;
        }
        List<User> customers = [
            SELECT Id FROM User
            WHERE Id = :userId AND Profile.Name = :CustomerRegistration.CUSTOMER_PROFILE_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        List<PermissionSet> permissionSets = [
            SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET_NAME WITH SYSTEM_MODE LIMIT 1
        ];
        if (customers.isEmpty() || permissionSets.isEmpty()) {
            return;
        }
        Id permissionSetId = permissionSets[0].Id;
        Integer existing = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetId = :permissionSetId
            WITH SYSTEM_MODE
        ];
        if (existing > 0) {
            return;
        }
        Database.insert(
            new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSetId),
            AccessLevel.SYSTEM_MODE
        );
    }
}
