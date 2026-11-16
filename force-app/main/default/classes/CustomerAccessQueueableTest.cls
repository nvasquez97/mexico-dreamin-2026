/**
 * Tests for CustomerAccessQueueable.
 * Covers AC-005.2 (the new customer gets the customer permission set) and BR-07.
 */
@IsTest
private class CustomerAccessQueueableTest {

    // Covers AC-005.2: a new site user receives the RutaCargo_Customer permission set.
    @IsTest
    static void shouldAssignCustomerPermissionSet_WhenRun() {
        User customer = TestDataFactory.createCustomerUser('Queue Test SA', 'Queuetest', null);
        Test.startTest();
        System.enqueueJob(new CustomerAccessQueueable(customer.Id));
        Test.stopTest();
        Assert.areEqual(1, [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :customer.Id AND PermissionSet.Name = 'RutaCargo_Customer'
            WITH SYSTEM_MODE
        ], 'Customer permission set assigned');
    }

    // Covers AC-005.2: running twice does not fail or duplicate the assignment.
    @IsTest
    static void shouldNotDuplicate_WhenAlreadyAssigned() {
        User customer = TestDataFactory.createCustomerUser('Queue Twice SA', 'Queuetwice', 'RutaCargo_Customer');
        Test.startTest();
        System.enqueueJob(new CustomerAccessQueueable(customer.Id));
        Test.stopTest();
        Assert.areEqual(1, [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :customer.Id AND PermissionSet.Name = 'RutaCargo_Customer'
            WITH SYSTEM_MODE
        ], 'Still one assignment');
    }

    // Covers BR-07: an internal user is never given the customer permission set by this job.
    @IsTest
    static void shouldIgnore_WhenUserIsNotASiteCustomer() {
        Test.startTest();
        System.enqueueJob(new CustomerAccessQueueable(UserInfo.getUserId()));
        Test.stopTest();
        Assert.areEqual(0, [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSet.Name = 'RutaCargo_Customer'
            WITH SYSTEM_MODE
        ], 'Internal user not assigned');
    }
}
