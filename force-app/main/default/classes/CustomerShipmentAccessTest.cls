/**
 * @description Customer access to shipments (odd/tasks/req-006-007-customer-shipments.md,
 *              S2, T1 Read step). Runs as the two seeded customer users (Ana López,
 *              Abarrotes Acme; Marta Ruiz, Globex Farma): the sharing set "RutaCargo
 *              Customer Shipments" (Shipment__c.Account__c = User.Account, Read) gives
 *              each one exactly the shipments of their own account, and the permission
 *              set RutaCargo_Customer gives Read and Create on Shipment__c (T2, Create
 *              step), read FLS on the AC-007 list and detail fields and create FLS on
 *              the AC-006.1 entered fields the customer may read, never on the four
 *              recipient-owned fields (Recipient_Address__c, Recipient_Phone__c,
 *              Recipient_Email__c, Delivery_Instructions__c: BR-02, G7, T2 fix), so a
 *              customer reads neither them nor, by the platform's FLS rule on field
 *              history (hardening-1 H5), their field history. No portal user is
 *              inserted (req-005 F7): the seeded users are queried; no test reads
 *              org data (no SeeAllData).
 */
@IsTest
private with sharing class CustomerShipmentAccessTest {

    // 251 shipments per account: more than one 200-record trigger batch.
    private static final Integer SHIPMENTS_PER_ACCOUNT = 251;

    // S2, T2: the custom Shipment__c fields RutaCargo_Customer may read: exactly
    // the 17 fields of T1. Never the four recipient-owned fields (BR-02, G7:
    // RECIPIENT_OWNED_FIELDS). Account__c (a required lookup, no FLS can be
    // granted on it) is not among them: the describe reports it not accessible
    // to a customer without Read on Account (G2).
    private static final Set<String> READABLE_CUSTOM_FIELDS = new Set<String>{
        'status__c', 'service_type__c', 'price__c', 'estimated_delivery__c',
        'pickup_address__c', 'pickup_date__c', 'pickup_postal_code__c',
        'origin_city__c', 'destination_city__c', 'destination_postal_code__c',
        'recipient_name__c', 'package_description__c', 'weight_kg__c',
        'declared_value__c', 'customer_reference__c', 'last_location__c', 'last_update__c'
    };

    // S2, T2: the AC-006.1 entered fields RutaCargo_Customer may write on
    // create: the 12 the customer may also read. ShipmentRequestController
    // stores the four recipient-owned ones through the trigger (T2 fix).
    private static final Set<String> CREATEABLE_CUSTOM_FIELDS = new Set<String>{
        'pickup_address__c', 'origin_city__c', 'pickup_postal_code__c', 'pickup_date__c',
        'recipient_name__c', 'destination_city__c', 'destination_postal_code__c',
        'service_type__c', 'weight_kg__c', 'package_description__c', 'declared_value__c', 'customer_reference__c'
    };

    // BR-02 (G7): fields the recipient owns; the customer can neither read nor write them.
    private static final List<String> RECIPIENT_OWNED_FIELDS = new List<String>{
        'Recipient_Address__c', 'Recipient_Phone__c', 'Recipient_Email__c', 'Delivery_Instructions__c'
    };

    // Two fields the customer must read on the same shipment: the control that
    // a refused field query is FLS, not a missing record.
    private static final List<String> CUSTOMER_READABLE_CONTROL_FIELDS = new List<String>{
        'Recipient_Name__c', 'Destination_City__c'
    };

    // Shipments of both seeded accounts, inserted by the record-access tests.
    private static void insertShipmentsOfBothAccounts() {
        List<Shipment__c> shipments = new List<Shipment__c>();
        shipments.addAll(TestDataFactory.newShipments(accountIdOf(TestDataFactory.SEEDED_CUSTOMER_EMAIL), SHIPMENTS_PER_ACCOUNT));
        shipments.addAll(TestDataFactory.newShipments(accountIdOf(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL), SHIPMENTS_PER_ACCOUNT));
        TestDataFactory.insertShipmentsWithCodes(shipments);
    }

    // ─── Record access through the sharing set (AC-006.7, AC-007.1) ─────────

    @IsTest
    static void anaReadsEveryShipmentOfHerAccount() {
        // AC-006.7 / AC-007.1: customer A (Ana López) reads her own account's shipments.
        insertShipmentsOfBothAccounts();
        User ana = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        Set<Id> own = shipmentIdsOfAccount(accountIdOf(TestDataFactory.SEEDED_CUSTOMER_EMAIL));
        Set<Id> visible;
        Test.startTest();
        System.runAs(ana) {
            visible = visibleShipmentIds(own);
        }
        Test.stopTest();
        Assert.areEqual(SHIPMENTS_PER_ACCOUNT, own.size(), 'Setup must create Ana\'s shipments');
        Assert.areEqual(own, visible, 'Ana must read every shipment of her own account');
    }

    @IsTest
    static void martaReadsEveryShipmentOfHerAccount() {
        // AC-006.7 / AC-007.1: customer B (Marta Ruiz) reads her own account's shipments.
        insertShipmentsOfBothAccounts();
        User marta = TestDataFactory.seededCustomerUser(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL);
        Set<Id> own = shipmentIdsOfAccount(accountIdOf(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL));
        Set<Id> visible;
        Test.startTest();
        System.runAs(marta) {
            visible = visibleShipmentIds(own);
        }
        Test.stopTest();
        Assert.areEqual(SHIPMENTS_PER_ACCOUNT, own.size(), 'Setup must create Marta\'s shipments');
        Assert.areEqual(own, visible, 'Marta must read every shipment of her own account');
    }

    @IsTest
    static void anaReadsNoneOfMartasShipments() {
        // AC-006.7 / AC-007.1 (BR-07): customer A reads none of customer B's shipments.
        insertShipmentsOfBothAccounts();
        User ana = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        Set<Id> martas = shipmentIdsOfAccount(accountIdOf(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL));
        Set<Id> visible;
        Test.startTest();
        System.runAs(ana) {
            visible = visibleShipmentIds(martas);
        }
        Test.stopTest();
        Assert.areEqual(SHIPMENTS_PER_ACCOUNT, martas.size(), 'Setup must create Marta\'s shipments');
        Assert.areEqual(0, visible.size(), 'Ana must read none of Marta\'s shipments');
    }

    @IsTest
    static void martaReadsNoneOfAnasShipments() {
        // AC-006.7 / AC-007.1 (BR-07): customer B reads none of customer A's shipments.
        insertShipmentsOfBothAccounts();
        User marta = TestDataFactory.seededCustomerUser(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL);
        Set<Id> anas = shipmentIdsOfAccount(accountIdOf(TestDataFactory.SEEDED_CUSTOMER_EMAIL));
        Set<Id> visible;
        Test.startTest();
        System.runAs(marta) {
            visible = visibleShipmentIds(anas);
        }
        Test.stopTest();
        Assert.areEqual(SHIPMENTS_PER_ACCOUNT, anas.size(), 'Setup must create Ana\'s shipments');
        Assert.areEqual(0, visible.size(), 'Marta must read none of Ana\'s shipments');
    }

    // ─── Object and field permissions (AC-006.7, T2 grants) ─────────────────

    @IsTest
    static void customerHasReadAndCreateOnlyOnShipments() {
        // AC-006.7: T2 grants Read and Create on Shipment__c and no Edit or Delete.
        User customer = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        Schema.DescribeSObjectResult shipment;
        Test.startTest();
        System.runAs(customer) {
            shipment = Shipment__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED);
        }
        Test.stopTest();
        String actual = 'read=' + shipment.isAccessible() + ' create=' + shipment.isCreateable()
            + ' edit=' + shipment.isUpdateable() + ' delete=' + shipment.isDeletable();
        Assert.areEqual('read=true create=true edit=false delete=false', actual,
            'RutaCargo_Customer must grant exactly Read and Create on Shipment__c in T2');
    }

    @IsTest
    static void customerReadsExactlyTheAc007Fields() {
        // AC-006.7 (BR-02, BR-03, P4, G7): read FLS on exactly the AC-007 list and
        // detail fields; nothing on the recipient's address, phone, email or
        // delivery instructions, nor on cost, margin, notes, hash or Proof_Id__c.
        User customer = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        Set<String> readable = new Set<String>();
        Test.startTest();
        System.runAs(customer) {
            Schema.DescribeSObjectResult shipment = Shipment__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED);
            for (Schema.SObjectField field : shipment.fields.getMap().values()) {
                Schema.DescribeFieldResult describe = field.getDescribe();
                if (describe.isCustom() && describe.isAccessible()) {
                    readable.add(describe.getName().toLowerCase());
                }
            }
        }
        Test.stopTest();
        Assert.areEqual(READABLE_CUSTOM_FIELDS, readable,
            'RutaCargo_Customer must make exactly the T2 custom fields readable on Shipment__c');
    }

    @IsTest
    static void customerCreatesExactlyTheAc0061Fields() {
        // AC-006.7 (X6, BR-02): create FLS on exactly the 12 AC-006.1 entered fields
        // the customer may read; never on the 4 recipient-owned fields, price,
        // status, estimate, cost, notes, hash, proof or the last update
        User customer = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        Set<String> createable = new Set<String>();
        Test.startTest();
        System.runAs(customer) {
            Schema.DescribeSObjectResult shipment = Shipment__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED);
            for (Schema.SObjectField field : shipment.fields.getMap().values()) {
                Schema.DescribeFieldResult describe = field.getDescribe();
                if (describe.isCustom() && describe.isCreateable()) {
                    createable.add(describe.getName().toLowerCase());
                }
            }
        }
        Test.stopTest();
        Assert.areEqual(CREATEABLE_CUSTOM_FIELDS, createable,
            'RutaCargo_Customer must make exactly the 12 readable AC-006.1 custom fields createable on Shipment__c');
    }

    @IsTest
    static void customerCannotReadAccounts() {
        // AC-006.7 (G2, G8): no Account access and no credit field.
        User customer = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        Boolean accountReadable;
        Test.startTest();
        System.runAs(customer) {
            accountReadable = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible();
        }
        Test.stopTest();
        Assert.isFalse(accountReadable, 'A customer must not have Read on Account (G2)');
    }

    // ─── Recipient-owned fields (BR-02, G7, T2 fix) ─────────────────────────

    @IsTest
    static void anaCannotReadTheRecipientOwnedFieldsOfHerOwnShipment() {
        // AC-006.7 / AC-007.3 (BR-02, P4, G7): in user mode Ana cannot read the
        // recipient's address, phone, email or delivery instructions of a shipment
        // of her own account (the API, not only the DTO, refuses them)
        User ana = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        Id ownShipmentId = insertOneShipmentOfAna();
        List<String> readable;
        Test.startTest();
        System.runAs(ana) {
            readable = fieldsReadableInUserMode(ownShipmentId, RECIPIENT_OWNED_FIELDS);
        }
        Test.stopTest();
        Assert.areEqual(new List<String>(), readable,
            'Ana must not read any recipient-owned field of her own shipment in user mode');
    }

    @IsTest
    static void anaReadsTheRecipientNameAndCityOfHerOwnShipment() {
        // AC-007.3 (control of the test above): the same user-mode field query
        // returns the recipient's name and destination city of the same shipment
        User ana = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        Id ownShipmentId = insertOneShipmentOfAna();
        List<String> readable;
        Test.startTest();
        System.runAs(ana) {
            readable = fieldsReadableInUserMode(ownShipmentId, CUSTOMER_READABLE_CONTROL_FIELDS);
        }
        Test.stopTest();
        Assert.areEqual(CUSTOMER_READABLE_CONTROL_FIELDS, readable,
            'Ana must read the recipient name and destination city of her own shipment');
    }

    // H5 (hardening-1, CA-002): the platform shows a field-history entry only
    // to a user who can read the field, so Ana, who has no read FLS on
    // Delivery_Instructions__c, reads none of its history rows. This test needs
    // no org data: it proves the FLS side by describe; the user-mode refusal is
    // proven by anaCannotReadTheRecipientOwnedFieldsOfHerOwnShipment. The former
    // SeeAllData history test last ran green in the gate @ 56bac29.
    @IsTest
    static void anaCannotAccessTheDeliveryInstructionsByDescribe() {
        // AC-006.7 / AC-H5.2 (BR-02, P4, G7, G9): as Ana the describe reports
        // Delivery_Instructions__c not accessible, so no history of it is shown
        User ana = TestDataFactory.seededCustomerUser(TestDataFactory.SEEDED_CUSTOMER_EMAIL);
        Boolean instructionsAccessible;
        Test.startTest();
        System.runAs(ana) {
            instructionsAccessible = Schema.SObjectType.Shipment__c.fields.Delivery_Instructions__c.isAccessible();
        }
        Test.stopTest();
        Assert.isFalse(instructionsAccessible,
            'Ana must not have read access to Delivery_Instructions__c, so its field history stays hidden from her');
    }

    // ─── Helpers ────────────────────────────────────────────────────────────

    // Runs in the caller's System.runAs context, in user mode: sharing and the
    // object permission of the running user apply.
    private static Set<Id> visibleShipmentIds(Set<Id> candidates) {
        return new Map<Id, Shipment__c>([
            SELECT Id FROM Shipment__c WHERE Id IN :candidates WITH USER_MODE
        ]).keySet();
    }

    private static Set<Id> shipmentIdsOfAccount(Id accountId) {
        return new Map<Id, Shipment__c>([
            SELECT Id FROM Shipment__c WHERE Account__c = :accountId
            // SECURITY-JUSTIFICATION: test setup read as the test's administrator, outside
            // System.runAs: the fixture's Ids or account the customer cannot
            // read. Scope: this test class only; compensating control: every check under
            // test runs inside System.runAs as a customer, in user mode.
            // (pending owner approval, 2026-11-18)
            WITH SYSTEM_MODE
        ]).keySet();
    }

    private static Id accountIdOf(String email) {
        Id userId = TestDataFactory.seededCustomerUser(email).Id;
        return [
            SELECT AccountId FROM User WHERE Id = :userId
            // SECURITY-JUSTIFICATION: test setup read as the test's administrator, outside
            // System.runAs: the fixture's Ids or account the customer cannot
            // read. Scope: this test class only; compensating control: every check under
            // test runs inside System.runAs as a customer, in user mode.
            // (pending owner approval, 2026-11-18)
            WITH SYSTEM_MODE
        ].AccountId;
    }

    // Each field whose user-mode query on the shipment succeeds, in the given
    // order. The field names come only from the constant lists of this class.
    private static List<String> fieldsReadableInUserMode(Id shipmentId, List<String> fieldNames) {
        List<String> readable = new List<String>();
        for (String fieldName : fieldNames) {
            try {
                List<Shipment__c> rows = Database.queryWithBinds(
                    'SELECT ' + fieldName + ' FROM Shipment__c WHERE Id = :shipmentId',
                    new Map<String, Object>{ 'shipmentId' => shipmentId }, AccessLevel.USER_MODE);
                if (rows.size() == 1) {
                    readable.add(fieldName);
                }
            } catch (QueryException e) {
                continue;
            }
        }
        return readable;
    }

    private static Id insertOneShipmentOfAna() {
        List<Shipment__c> shipments = TestDataFactory.newShipments(accountIdOf(TestDataFactory.SEEDED_CUSTOMER_EMAIL), 1);
        TestDataFactory.insertShipmentsWithCodes(shipments);
        return shipments[0].Id;
    }
}
