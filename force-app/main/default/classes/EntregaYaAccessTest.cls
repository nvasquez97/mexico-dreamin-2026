/**
 * @description Proves the least-privilege access of the EntregaYa integration
 *              (req-004 S3, AC-004.5 permission-set facts, BR-04, BR-09): the
 *              RutaCargo_EntregaYa_Integration permission set (object and field
 *              permissions, custom permission RutaCargo_EntregaYa_Sender) and the
 *              RutaCargo_EntregaYa_Integration public group.
 *              Users: one integration user (profile "Minimum Access - API Only
 *              Integrations", Salesforce Integration license; the org has 1, so
 *              never more than 1 here) with the "Salesforce API Integration"
 *              permission set license, the permission set and the group. The
 *              real integration user (T4) is reused when it already holds that
 *              license; otherwise setup creates one. And one
 *              support agent (Standard Platform User with RutaCargo_Support_Agent).
 *              Every account and shipment is owned by the running admin, so the
 *              integration user's record access comes only from the group shares.
 *              Criteria-based sharing rules are not evaluated in Apex tests (A10):
 *              setup mirrors the deployed rule with manual Edit shares to the
 *              group. The deployed rule, the class access and the user
 *              permissions are proven by scripts/checks/entregaya-access-check.sh.
 */
@IsTest
private with sharing class EntregaYaAccessTest {

    private static final String PERMISSION_SET_NAME = 'RutaCargo_EntregaYa_Integration';
    private static final String AGENT_PERMISSION_SET_NAME = 'RutaCargo_Support_Agent';
    private static final String GROUP_NAME = 'RutaCargo_EntregaYa_Integration';
    private static final String SENDER_PERMISSION = 'RutaCargo_EntregaYa_Sender';

    private static final String INTEGRATION_KEY = 'rceyint';
    private static final String AGENT_KEY = 'rceyagt';
    private static final String CUSTOMER_NAME = 'EntregaYa Access Customer';

    private static final Integer BULK_SIZE = 251;
    private static final String RULE_ACCESS = 'Edit';

    /** The only Shipment__c fields the integration may read and edit (S3). */
    private static final Set<String> STATUS_FIELDS = new Set<String>{
        'Status__c', 'Last_Location__c', 'Last_Update__c', 'Delivered_At__c', 'Proof_Id__c'
    };

    // ─── Setup and helpers ────────────────────────────────────────────────

    // SECURITY-JUSTIFICATION: the running test admin has no field permissions on
    // the RutaCargo custom fields (at API 67 DML and SOQL default to user mode),
    // so the test fixture is written and read back in system mode. Scope: setup
    // DML and verification reads of this test class only. Compensating control:
    // every action of the users under test runs inside System.runAs in USER_MODE.
    // (pending owner approval, 2026-11-17)
    private static void insertAsSystem(List<SObject> records) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
    }

    private static Id permissionSetId(String name) {
        List<PermissionSet> sets = [SELECT Id FROM PermissionSet WHERE Name = :name WITH SYSTEM_MODE];
        Assert.areEqual(1, sets.size(), 'Permission set ' + name + ' must exist in the org');
        return sets[0].Id;
    }

    private static Id groupId() {
        List<Group> groups = [
            SELECT Id FROM Group WHERE DeveloperName = :GROUP_NAME AND Type = 'Regular' WITH SYSTEM_MODE
        ];
        Assert.areEqual(1, groups.size(), 'Public group ' + GROUP_NAME + ' must exist in the org');
        return groups[0].Id;
    }

    @TestSetup
    static void setup() {
        // The org's only Salesforce Integration license may already be held by the
        // real integration user (T4): the factory then returns that saved user.
        User integration = TestDataFactory.newOrExistingIntegrationUser(INTEGRATION_KEY);
        Boolean isNewIntegrationUser = integration.Id == null;
        User agent = TestDataFactory.newPlatformUsers(new List<String>{ AGENT_KEY })[0];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<User> newUsers = new List<User>{ agent };
            if (isNewIntegrationUser) {
                newUsers.add(integration);
            }
            insertAsSystem(newUsers);
            if (isNewIntegrationUser) {
                insertAsSystem(new List<PermissionSetLicenseAssign>{
                    TestDataFactory.newApiIntegrationLicenseAssignment(integration.Id) });
            }
            List<PermissionSetAssignment> assignments = TestDataFactory.newPermissionSetAssignments(
                permissionSetId(AGENT_PERMISSION_SET_NAME), new List<User>{ agent });
            Id integrationSetId = permissionSetId(PERMISSION_SET_NAME);
            if ([SELECT COUNT() FROM PermissionSetAssignment
                    WHERE AssigneeId = :integration.Id AND PermissionSetId = :integrationSetId WITH SYSTEM_MODE] == 0) {
                assignments.addAll(TestDataFactory.newPermissionSetAssignments(
                    integrationSetId, new List<User>{ integration }));
            }
            insertAsSystem(assignments);
            Id integrationGroupId = groupId();
            if ([SELECT COUNT() FROM GroupMember
                    WHERE GroupId = :integrationGroupId AND UserOrGroupId = :integration.Id WITH SYSTEM_MODE] == 0) {
                insertAsSystem(TestDataFactory.newGroupMembers(integrationGroupId, new List<User>{ integration }));
            }
        }

        Account customer = TestDataFactory.newCustomerAccount(CUSTOMER_NAME);
        insertAsSystem(new List<Account>{ customer });
        List<Shipment__c> shipments = TestDataFactory.newShipments(customer.Id, BULK_SIZE);
        for (Shipment__c shipment : shipments) {
            shipment.Price__c = 300;
            shipment.Carrier_Cost__c = 120;
            shipment.Internal_Notes__c = 'Internal note';
        }
        insertAsSystem(shipments);
        // Mirrors the deployed criteria-based rule (A10): every shipment shared
        // Read/Write with the EntregaYa integration group.
        insertAsSystem(TestDataFactory.newShipmentGroupShares(shipments, groupId(), RULE_ACCESS));
    }

    private static User userWithKey(String key) {
        String username = key + '.' + UserInfo.getOrganizationId() + '@example.com.rutacargo';
        return [SELECT Id FROM User WHERE Username = :username WITH SYSTEM_MODE LIMIT 1];
    }

    /**
     * The integration user of the setup, created or reused: found through its
     * group membership, independently of the factory's own lookup.
     * @return the only integration-profile user in group RutaCargo_EntregaYa_Integration
     */
    private static User integrationUser() {
        List<User> members = [
            SELECT Id FROM User
            WHERE Profile.Name = :TestDataFactory.INTEGRATION_PROFILE_NAME
                AND Id IN (SELECT UserOrGroupId FROM GroupMember WHERE Group.DeveloperName = :GROUP_NAME)
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(1, members.size(), 'Exactly one integration user must be in group ' + GROUP_NAME);
        return members[0];
    }

    private static List<Shipment__c> twoShipments() {
        return [SELECT Id FROM Shipment__c WITH SYSTEM_MODE ORDER BY Name LIMIT 2];
    }

    private static Schema.DescribeSObjectResult describeShipment() {
        return Shipment__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED);
    }

    // ─── AC-004.5 (P4): field-level security of the integration user ──────

    @IsTest
    static void integrationUser_readsAndEditsTheFiveStatusFields() {
        // AC-004.5: read/edit FLS on Status__c, Last_Location__c, Last_Update__c, Delivered_At__c, Proof_Id__c
        List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
            Shipment__c.Status__c, Shipment__c.Last_Location__c, Shipment__c.Last_Update__c,
            Shipment__c.Delivered_At__c, Shipment__c.Proof_Id__c
        };
        List<String> wrong = new List<String>();
        Test.startTest();
        System.runAs(integrationUser()) {
            for (Schema.SObjectField field : fields) {
                Schema.DescribeFieldResult result = field.getDescribe();
                if (!result.isAccessible() || !result.isUpdateable()) {
                    wrong.add(result.getName());
                }
            }
        }
        Test.stopTest();
        Assert.areEqual(new List<String>(), wrong, 'The integration user must read and edit these status fields');
    }

    @IsTest
    static void integrationUser_readsNoCustomFieldButTheFiveStatusFields() {
        // AC-004.5: read/edit FLS only on the five status fields (no other custom field)
        Set<String> readable = new Set<String>();
        Test.startTest();
        System.runAs(integrationUser()) {
            for (Schema.SObjectField field : describeShipment().fields.getMap().values()) {
                Schema.DescribeFieldResult result = field.getDescribe();
                if (result.isCustom() && result.isAccessible()) {
                    readable.add(result.getName());
                }
            }
        }
        Test.stopTest();
        Assert.areEqual(STATUS_FIELDS, readable, 'The integration user must read exactly the five status fields');
    }

    @IsTest
    static void integrationUser_cannotReadRecipientPriceCostNotesOrAccessCodeHash() {
        // AC-004.5: nothing on Delivery_Access_Code_Hash__c, Recipient_*, Price__c, Carrier_Cost__c, Internal_Notes__c
        List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
            Shipment__c.Recipient_Name__c, Shipment__c.Recipient_Address__c, Shipment__c.Recipient_Phone__c,
            Shipment__c.Recipient_Email__c, Shipment__c.Price__c, Shipment__c.Carrier_Cost__c,
            Shipment__c.Internal_Notes__c, Shipment__c.Delivery_Access_Code_Hash__c
        };
        List<String> readable = new List<String>();
        Test.startTest();
        System.runAs(integrationUser()) {
            for (Schema.SObjectField field : fields) {
                Schema.DescribeFieldResult result = field.getDescribe();
                if (result.isAccessible()) {
                    readable.add(result.getName());
                }
            }
        }
        Test.stopTest();
        Assert.areEqual(new List<String>(), readable, 'The integration user must not read these fields');
    }

    // ─── AC-004.5 (P4): object permissions and record access ──────────────

    @IsTest
    static void integrationUser_cannotCreateShipments() {
        // AC-004.5: Shipment__c Read and Edit only (no Create)
        Boolean createable;
        Test.startTest();
        System.runAs(integrationUser()) {
            createable = describeShipment().isCreateable();
        }
        Test.stopTest();
        Assert.isFalse(createable, 'Shipment__c must not be createable for the integration user');
    }

    @IsTest
    static void integrationUser_cannotDeleteShipments() {
        // AC-004.5: Shipment__c Read and Edit only (no Delete)
        Boolean deletable;
        Test.startTest();
        System.runAs(integrationUser()) {
            deletable = describeShipment().isDeletable();
        }
        Test.stopTest();
        Assert.isFalse(deletable, 'Shipment__c must not be deletable for the integration user');
    }

    @IsTest
    static void integrationUser_readsEveryShipmentSharedWithTheGroup() {
        // AC-004.5 (S3): the group share gives the integration user read access to every shipment
        Integer visible;
        String failure;
        Test.startTest();
        System.runAs(integrationUser()) {
            try {
                visible = [SELECT COUNT() FROM Shipment__c WITH USER_MODE];
            } catch (QueryException e) {
                failure = e.getMessage();
            } catch (SecurityException e) {
                failure = e.getMessage();
            }
        }
        Test.stopTest();
        Assert.isNull(failure, 'The integration user must be able to query shipments');
        Assert.areEqual(BULK_SIZE, visible, 'The integration user must read all ' + BULK_SIZE + ' shared shipments');
    }

    @IsTest
    static void integrationUser_directUpdateOfStatusFieldsIsRefused() {
        // AC-004.9 (T2 decision): a direct update of the status fields by the integration user is
        // refused with the generic message and nothing changes; edit rights on the five fields are
        // proven by describe in integrationUser_readsAndEditsTheFiveStatusFields, the update through
        // the service in EntregaYaStatusServiceTest
        List<Shipment__c> shared = twoShipments();
        Datetime first = Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0);
        Datetime second = Datetime.newInstanceGmt(2026, 11, 21, 15, 5, 0);
        List<Shipment__c> changes = new List<Shipment__c>{
            new Shipment__c(Id = shared[0].Id, Status__c = 'Out for delivery',
                Last_Location__c = 'Monterrey, NL', Last_Update__c = first),
            new Shipment__c(Id = shared[1].Id, Status__c = 'Delivered', Last_Location__c = 'Guadalajara, JAL',
                Last_Update__c = second, Delivered_At__c = second, Proof_Id__c = 'PRF-90417')
        };
        List<Database.SaveResult> results;
        Test.startTest();
        System.runAs(integrationUser()) {
            results = Database.update(changes, false, AccessLevel.USER_MODE);
        }
        Test.stopTest();
        String refusal = 'Status updates from EntregaYa must use the status service.';
        Assert.areEqual(refusal + '|' + refusal,
            (results[0].isSuccess() ? 'success' : results[0].getErrors()[0].getMessage()) + '|'
                + (results[1].isSuccess() ? 'success' : results[1].getErrors()[0].getMessage()),
            'Both direct updates must be refused with the generic message');
        for (Shipment__c row : [
            SELECT Status__c, Last_Location__c, Last_Update__c, Delivered_At__c, Proof_Id__c
            FROM Shipment__c WHERE Id IN :changes WITH SYSTEM_MODE
        ]) {
            Assert.areEqual('Requested|null|null|null|null', row.Status__c + '|' + row.Last_Location__c + '|'
                + row.Last_Update__c + '|' + row.Delivered_At__c + '|' + row.Proof_Id__c,
                'A refused direct update must change nothing');
        }
    }

    @IsTest
    static void integrationUser_cannotUpdatePrice() {
        // AC-004.5: no edit on fields outside the five status fields (Price__c), proven by describe
        // so it does not depend on the AC-004.9 trigger guard
        Boolean updateable;
        Test.startTest();
        System.runAs(integrationUser()) {
            updateable = Shipment__c.Price__c.getDescribe().isUpdateable();
        }
        Test.stopTest();
        Assert.isFalse(updateable, 'The integration user must not be able to edit Price__c');
    }

    // ─── AC-004.5 (BR-04, BR-09): the custom permission ───────────────────

    @IsTest
    static void integrationUser_holdsTheSenderCustomPermission() {
        // AC-004.5: RutaCargo_EntregaYa_Sender is granted through RutaCargo_EntregaYa_Integration
        Boolean granted;
        Test.startTest();
        System.runAs(integrationUser()) {
            granted = FeatureManagement.checkPermission(SENDER_PERMISSION);
        }
        Test.stopTest();
        Assert.isTrue(granted, 'The integration user must hold ' + SENDER_PERMISSION);
    }

    @IsTest
    static void supportAgent_lacksTheSenderCustomPermission() {
        // AC-004.5 (BR-09): a support agent edits statuses by hand but never holds RutaCargo_EntregaYa_Sender
        Boolean granted;
        Test.startTest();
        System.runAs(userWithKey(AGENT_KEY)) {
            granted = FeatureManagement.checkPermission(SENDER_PERMISSION);
        }
        Test.stopTest();
        Assert.isFalse(granted, 'A support agent must not hold ' + SENDER_PERMISSION);
    }

    // ─── EntregaYaStatusResource without the custom permission ─────────────

    @IsTest
    static void statusResource_answers403WithAGenericBody_withoutTheSenderPermission() {
        // AC-004.5 (BR-04): a caller without RutaCargo_EntregaYa_Sender (here the running
        // admin, with an empty request) gets 403 FORBIDDEN with the generic body; nothing changes
        RestContext.request = new RestRequest();
        RestContext.response = new RestResponse();
        Test.startTest();
        EntregaYaStatusResource.post();
        Test.stopTest();
        Assert.areEqual(403, RestContext.response.statusCode, 'A caller without the custom permission must get 403');
        Assert.areEqual(new Map<String, Object>{ 'error' => new Map<String, Object>{
                'code' => 'FORBIDDEN', 'message' => 'This user may not send EntregaYa status updates.' } },
            JSON.deserializeUntyped(RestContext.response.responseBody.toString()),
            'The 403 must carry exactly the generic FORBIDDEN body');
        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c WHERE Last_Update__c != null WITH SYSTEM_MODE],
            'No shipment may receive a status update');
    }

    // ─── Test data: the org's only Salesforce Integration license ─────────

    @IsTest
    static void factory_reusesTheExistingIntegrationUser() {
        // AC-004.5 (T1 review finding 1): with an integration user already holding the
        // Salesforce API Integration PSL, the factory returns it for any key and builds no new user
        Id expected = integrationUser().Id;
        TestDataFactory.reuseExistingIntegrationUserOnly = true;
        User first;
        User second;
        Test.startTest();
        first = TestDataFactory.newOrExistingIntegrationUser('rceyone');
        second = TestDataFactory.newOrExistingIntegrationUser('rceytwo');
        Test.stopTest();
        Assert.areEqual(expected + '|' + expected, first.Id + '|' + second.Id,
            'Both keys must reuse the integration user that already holds the license');
    }
}
