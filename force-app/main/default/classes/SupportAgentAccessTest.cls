/**
 * @description Proves the least-privilege access of RutaCargo support agents:
 *              the RutaCargo_Support_Agent permission set (object and field
 *              permissions) and the RutaCargo_Support_Agents public group.
 *              Covers AC-F.7 and AC-F.8 of odd/tasks/foundation.md. AC-F.14 is
 *              proven by scripts/checks/shipment-access-check.sh.
 *              Users: a support agent (permission set and group), a user in the
 *              group without the permission set, and an agent with the
 *              permission set outside the group, all Standard Platform Users
 *              (3 Salesforce Platform licenses in the org: never more than 3).
 *              Every account and shipment is owned by the running admin, so an
 *              agent's record access comes only from the group shares.
 *              The platform does not evaluate criteria-based sharing rules in
 *              Apex tests (assumption A10), so setup mirrors the two deployed
 *              rules with manual Edit shares to the group: every shipment, and
 *              the customer accounts. The deployed rule definitions are proven
 *              by the check script; the real rule shares by T6 on seeded data.
 */
@IsTest
private with sharing class SupportAgentAccessTest {

    private static final String PERMISSION_SET_NAME = 'RutaCargo_Support_Agent';
    private static final String GROUP_NAME = 'RutaCargo_Support_Agents';

    private static final String AGENT_KEY = 'rcagent';
    private static final String NO_PERMISSION_SET_KEY = 'rcnops';
    private static final String NO_GROUP_KEY = 'rcnogrp';

    private static final String BUSINESS_ACCOUNT = 'Agent Test Business';
    private static final String INDIVIDUAL_ACCOUNT = 'Agent Test Individual';

    private static final Integer BULK_SIZE = 251;
    private static final String RULE_ACCESS = 'Edit';
    private static final String EVEN_NOTE = 'Even shipment internal note';
    private static final String ODD_NOTE = 'Odd shipment internal note';

    // ─── Setup and helpers ────────────────────────────────────────────────

    // SECURITY-JUSTIFICATION: the running test admin has no field permissions on
    // the RutaCargo custom fields (at API 67 DML and SOQL default to user mode),
    // so the test fixture is written and read back in system mode. Scope: setup
    // DML and verification reads of this test class only. Compensating control:
    // every action of the users under test runs inside System.runAs in USER_MODE.
    // (pending owner approval, 2026-11-18)
    private static void insertAsSystem(List<SObject> records) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
    }

    private static Id permissionSetId() {
        List<PermissionSet> sets = [SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET_NAME WITH SYSTEM_MODE];
        Assert.areEqual(1, sets.size(), 'Permission set ' + PERMISSION_SET_NAME + ' must exist in the org');
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
        List<User> users = TestDataFactory.newPlatformUsers(
            new List<String>{ AGENT_KEY, NO_PERMISSION_SET_KEY, NO_GROUP_KEY });
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insertAsSystem(users);
            insertAsSystem(TestDataFactory.newPermissionSetAssignments(permissionSetId(),
                new List<User>{ users[0], users[2] }));
            insertAsSystem(TestDataFactory.newGroupMembers(groupId(),
                new List<User>{ users[0], users[1] }));
        }

        Account business = TestDataFactory.newCustomerAccount(BUSINESS_ACCOUNT);
        business.Credit_Limit__c = 500000;
        business.Credit_Risk__c = 'Low';
        Account individual = TestDataFactory.newCustomerAccount(INDIVIDUAL_ACCOUNT);
        individual.Customer_Type__c = 'Individual';
        individual.Credit_Limit__c = 20000;
        individual.Credit_Risk__c = 'Medium';
        List<Account> customers = new List<Account>{ business, individual };
        insertAsSystem(customers);

        List<Shipment__c> shipments = TestDataFactory.newShipments(business.Id, BULK_SIZE);
        for (Integer i = 0; i < shipments.size(); i++) {
            Boolean even = Math.mod(i, 2) == 0;
            shipments[i].Price__c = even ? 200 : 400;
            shipments[i].Carrier_Cost__c = even ? 150 : 100;
            shipments[i].Internal_Notes__c = even ? EVEN_NOTE : ODD_NOTE;
        }
        insertAsSystem(shipments);

        // Mirrors the deployed criteria-based rules (A10): every shipment and every
        // customer account (Customer_Type__c set) shared Read/Write with the group.
        Id agentsGroupId = groupId();
        insertAsSystem(TestDataFactory.newShipmentGroupShares(shipments, agentsGroupId, RULE_ACCESS));
        insertAsSystem(TestDataFactory.newAccountGroupShares(customers, agentsGroupId, RULE_ACCESS));
    }

    private static User userWithKey(String key) {
        String username = key + '.' + UserInfo.getOrganizationId() + '@example.com.rutacargo';
        return [SELECT Id FROM User WHERE Username = :username WITH SYSTEM_MODE LIMIT 1];
    }

    private static Id accountId(String name) {
        return [SELECT Id FROM Account WHERE Name = :name WITH SYSTEM_MODE LIMIT 1].Id;
    }

    private static List<Shipment__c> twoSharedShipments() {
        return [
            SELECT Id FROM Shipment__c WHERE Account__r.Name = :BUSINESS_ACCOUNT
            WITH SYSTEM_MODE ORDER BY Name LIMIT 2
        ];
    }

    private static Schema.DescribeFieldResult describeField(Schema.SObjectField field) {
        return field.getDescribe();
    }

    // ─── AC-F.7 (BR-03, S3): read, create, edit; internal fields; no delete ──

    @IsTest
    static void supportAgent_readsEveryShipmentOfAnAccountTheyDoNotOwn() {
        // AC-F.7: the agent reads shipments of a customer account they do not own
        User agent = userWithKey(AGENT_KEY);
        List<Shipment__c> visible;
        Test.startTest();
        System.runAs(agent) {
            visible = [SELECT Id, OwnerId, Account__r.OwnerId FROM Shipment__c WITH USER_MODE];
        }
        Test.stopTest();
        Assert.areEqual(BULK_SIZE, visible.size(), 'The agent must read all ' + BULK_SIZE + ' shared shipments');
        for (Shipment__c shipment : visible) {
            Assert.areNotEqual(agent.Id, shipment.OwnerId, 'The agent must not own a shipment under test');
            Assert.areNotEqual(agent.Id, shipment.Account__r.OwnerId, 'The agent must not own the account under test');
        }
    }

    @IsTest
    static void supportAgent_readsCarrierCostMarginAndInternalNotes() {
        // AC-F.7: the agent can read Carrier_Cost__c, Margin__c and Internal_Notes__c
        Map<String, Integer> expected = new Map<String, Integer>{
            '150.00|25.00|' + EVEN_NOTE => 126,
            '100.00|75.00|' + ODD_NOTE => 125
        };
        Map<String, Integer> actual = new Map<String, Integer>();
        Test.startTest();
        System.runAs(userWithKey(AGENT_KEY)) {
            for (Shipment__c shipment : [
                SELECT Carrier_Cost__c, Margin__c, Internal_Notes__c FROM Shipment__c WITH USER_MODE
            ]) {
                String key = shipment.Carrier_Cost__c.setScale(2) + '|' + shipment.Margin__c.setScale(2)
                    + '|' + shipment.Internal_Notes__c;
                actual.put(key, actual.containsKey(key) ? actual.get(key) + 1 : 1);
            }
        }
        Test.stopTest();
        Assert.areEqual(expected, actual, 'The agent must read the exact carrier cost, margin and internal notes');
    }

    @IsTest
    static void supportAgent_readsCreditFieldsOfIndividualAndBusinessCustomers() {
        // AC-F.7: the agent can read Credit_Limit__c and Credit_Risk__c of customer accounts
        Map<String, String> expected = new Map<String, String>{
            BUSINESS_ACCOUNT => '500000.00|Low',
            INDIVIDUAL_ACCOUNT => '20000.00|Medium'
        };
        Map<String, String> actual = new Map<String, String>();
        Test.startTest();
        System.runAs(userWithKey(AGENT_KEY)) {
            for (Account customer : [
                SELECT Name, Credit_Limit__c, Credit_Risk__c FROM Account
                WHERE Name IN :expected.keySet() WITH USER_MODE
            ]) {
                actual.put(customer.Name, customer.Credit_Limit__c.setScale(2) + '|' + customer.Credit_Risk__c);
            }
        }
        Test.stopTest();
        Assert.areEqual(expected, actual, 'The agent must read the credit fields of both customer accounts');
    }

    @IsTest
    static void supportAgent_createsShipmentsForAnAccountTheyDoNotOwn() {
        // AC-F.7: the agent creates shipments of a customer account they do not own
        Id customerId = accountId(BUSINESS_ACCOUNT);
        List<Shipment__c> rows = TestDataFactory.newShipments(customerId, 2);
        rows[0].Price__c = 310;
        rows[1].Price__c = 520;
        Map<Id, String> codes;
        Test.startTest();
        System.runAs(userWithKey(AGENT_KEY)) {
            codes = DeliveryAccessCode.insertWithCodes(rows);
        }
        Test.stopTest();
        Map<Id, Shipment__c> created = new Map<Id, Shipment__c>([
            SELECT Id, Price__c, Status__c, Account__c FROM Shipment__c WHERE Id IN :codes.keySet() WITH SYSTEM_MODE
        ]);
        Assert.areEqual(2, codes.size(), 'insertWithCodes must return one code per created shipment');
        Assert.areEqual(2, created.size(), 'Both shipments created by the agent must exist');
        Assert.areEqual(310, created.get(rows[0].Id).Price__c, 'First created shipment keeps its price');
        Assert.areEqual(520, created.get(rows[1].Id).Price__c, 'Second created shipment keeps its price');
        Assert.areEqual('Requested', created.get(rows[0].Id).Status__c, 'First created shipment starts as Requested');
        Assert.areEqual('Requested', created.get(rows[1].Id).Status__c, 'Second created shipment starts as Requested');
        Assert.areEqual(customerId, created.get(rows[1].Id).Account__c, 'The shipment belongs to the shared account');
    }

    @IsTest
    static void supportAgent_editsShipmentsTheyDoNotOwn() {
        // AC-F.7: the agent edits shipments of a customer account they do not own
        List<Shipment__c> shared = twoSharedShipments();
        List<Shipment__c> changes = new List<Shipment__c>{
            new Shipment__c(Id = shared[0].Id, Carrier_Cost__c = 90, Internal_Notes__c = 'Agent edit one'),
            new Shipment__c(Id = shared[1].Id, Carrier_Cost__c = 120, Internal_Notes__c = 'Agent edit two')
        };
        Test.startTest();
        System.runAs(userWithKey(AGENT_KEY)) {
            Database.update(changes, AccessLevel.USER_MODE);
        }
        Test.stopTest();
        Map<Id, Shipment__c> saved = new Map<Id, Shipment__c>([
            SELECT Carrier_Cost__c, Internal_Notes__c FROM Shipment__c WHERE Id IN :changes WITH SYSTEM_MODE
        ]);
        Assert.areEqual(90, saved.get(shared[0].Id).Carrier_Cost__c, 'First edit must be saved');
        Assert.areEqual('Agent edit one', saved.get(shared[0].Id).Internal_Notes__c, 'First note must be saved');
        Assert.areEqual(120, saved.get(shared[1].Id).Carrier_Cost__c, 'Second edit must be saved');
        Assert.areEqual('Agent edit two', saved.get(shared[1].Id).Internal_Notes__c, 'Second note must be saved');
    }

    @IsTest
    static void supportAgent_cannotDeleteEvenAShipmentTheyCreated() {
        // AC-F.7: the agent cannot delete a shipment (not even one they own)
        Shipment__c own = TestDataFactory.newShipment(accountId(BUSINESS_ACCOUNT));
        List<Database.DeleteResult> results;
        Test.startTest();
        System.runAs(userWithKey(AGENT_KEY)) {
            DeliveryAccessCode.insertWithCodes(new List<Shipment__c>{ own });
            results = Database.delete(new List<Id>{ own.Id }, false, AccessLevel.USER_MODE);
        }
        Test.stopTest();
        Assert.isFalse(results[0].isSuccess(), 'The agent must not be able to delete a shipment');
        Assert.areEqual(1, [SELECT COUNT() FROM Shipment__c WHERE Id = :own.Id WITH SYSTEM_MODE],
            'The shipment must still exist after the delete attempt');
    }

    @IsTest
    static void supportAgent_shipmentObjectIsNotDeletable() {
        // AC-F.7: no Delete object permission on Shipment__c for the agent
        Boolean deletable;
        Test.startTest();
        System.runAs(userWithKey(AGENT_KEY)) {
            deletable = Shipment__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isDeletable();
        }
        Test.stopTest();
        Assert.isFalse(deletable, 'Shipment__c must not be deletable for a support agent');
    }

    @IsTest
    static void userWithoutPermissionSet_hasNoAccessToShipmentObject() {
        // AC-F.7: the same kind of user without the permission set cannot access Shipment__c
        Boolean accessible;
        Test.startTest();
        System.runAs(userWithKey(NO_PERMISSION_SET_KEY)) {
            accessible = Shipment__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible();
        }
        Test.stopTest();
        Assert.isFalse(accessible, 'Shipment__c must not be accessible without RutaCargo_Support_Agent');
    }

    @IsTest
    static void userWithoutPermissionSet_cannotQueryShipments() {
        // AC-F.7: the same kind of user without the permission set cannot read shipments
        String failure;
        Test.startTest();
        System.runAs(userWithKey(NO_PERMISSION_SET_KEY)) {
            try {
                List<Shipment__c> rows = [SELECT Id FROM Shipment__c WITH USER_MODE];
                failure = 'read ' + rows.size() + ' shipments';
            } catch (QueryException expected) {
                failure = null;
            }
        }
        Test.stopTest();
        Assert.isNull(failure, 'A user without the permission set must get a QueryException, but ' + failure);
    }

    @IsTest
    static void agentOutsideTheGroup_seesNoShipment() {
        // AC-F.7 (A2): record access comes from the group shares, not from the permission set
        Integer visible;
        Test.startTest();
        System.runAs(userWithKey(NO_GROUP_KEY)) {
            visible = [SELECT COUNT() FROM Shipment__c WITH USER_MODE];
        }
        Test.stopTest();
        Assert.areEqual(0, visible, 'An agent outside RutaCargo_Support_Agents must not see shared shipments');
    }

    // ─── AC-F.8 (BR-09, D1): field-level security of the agent ────────────

    @IsTest
    static void supportAgent_systemFieldsAreReadableButNotUpdateable() {
        // AC-F.8: Name, Margin__c and Original_Estimated_Delivery__c are readable, not updateable
        List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
            Shipment__c.Name, Shipment__c.Margin__c, Shipment__c.Original_Estimated_Delivery__c
        };
        List<String> wrong = new List<String>();
        Test.startTest();
        System.runAs(userWithKey(AGENT_KEY)) {
            for (Schema.SObjectField field : fields) {
                Schema.DescribeFieldResult result = describeField(field);
                if (!result.isAccessible() || result.isUpdateable()) {
                    wrong.add(result.getName());
                }
            }
        }
        Test.stopTest();
        Assert.areEqual(new List<String>(), wrong, 'These fields must be readable and not updateable for the agent');
    }

    @IsTest
    static void supportAgent_cannotReadTheAccessCodeHash() {
        // AC-F.8 (D1): Delivery_Access_Code_Hash__c is not readable by the agent
        Boolean readable;
        Test.startTest();
        System.runAs(userWithKey(AGENT_KEY)) {
            readable = describeField(Shipment__c.Delivery_Access_Code_Hash__c).isAccessible();
        }
        Test.stopTest();
        Assert.isFalse(readable, 'Delivery_Access_Code_Hash__c must not be readable by a support agent');
    }

    @IsTest
    static void supportAgent_operationalFieldsAreUpdateable() {
        // AC-F.8 (contrast): the fields an agent works with stay editable
        List<Schema.SObjectField> fields = new List<Schema.SObjectField>{
            Shipment__c.Status__c, Shipment__c.Estimated_Delivery__c, Shipment__c.Carrier_Cost__c,
            Shipment__c.Internal_Notes__c, Account.Credit_Limit__c, Account.Credit_Risk__c
        };
        List<String> wrong = new List<String>();
        Test.startTest();
        System.runAs(userWithKey(AGENT_KEY)) {
            for (Schema.SObjectField field : fields) {
                Schema.DescribeFieldResult result = describeField(field);
                if (!result.isUpdateable()) {
                    wrong.add(result.getName());
                }
            }
        }
        Test.stopTest();
        Assert.areEqual(new List<String>(), wrong, 'These fields must be updateable for the agent');
    }
}
