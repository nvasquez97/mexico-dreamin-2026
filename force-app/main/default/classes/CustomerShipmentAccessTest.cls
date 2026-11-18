/**
 * @description Customer access to shipments (odd/tasks/req-006-007-customer-shipments.md,
 *              S2, T1 Read step). Runs as the two seeded customer users (Ana López,
 *              Abarrotes Acme; Marta Ruiz, Globex Farma): the sharing set "RutaCargo
 *              Customer Shipments" (Shipment__c.Account__c = User.Account, Read) gives
 *              each one exactly the shipments of their own account, and the permission
 *              set RutaCargo_Customer gives Read and Create on Shipment__c (T2, Create
 *              step), read FLS on the AC-007 list and detail fields and create FLS on
 *              the AC-006.1 entered fields only. No portal user is inserted (req-005
 *              F7): the seeded users are queried.
 */
@IsTest
private with sharing class CustomerShipmentAccessTest {

    // 251 shipments per account: more than one 200-record trigger batch.
    private static final Integer SHIPMENTS_PER_ACCOUNT = 251;

    // S2, T2: the custom Shipment__c fields RutaCargo_Customer may read: the 17
    // fields of T1 plus the 4 recipient fields that their create FLS makes
    // readable (G7 residual: Recipient_Address__c, Recipient_Phone__c,
    // Recipient_Email__c, Delivery_Instructions__c). Account__c (a required
    // lookup, no FLS can be granted on it) is not among them: the describe
    // reports it not accessible to a customer without Read on Account (G2).
    private static final Set<String> READABLE_CUSTOM_FIELDS = new Set<String>{
        'status__c', 'service_type__c', 'price__c', 'estimated_delivery__c',
        'pickup_address__c', 'pickup_date__c', 'pickup_postal_code__c',
        'origin_city__c', 'destination_city__c', 'destination_postal_code__c',
        'recipient_name__c', 'package_description__c', 'weight_kg__c',
        'declared_value__c', 'customer_reference__c', 'last_location__c', 'last_update__c',
        'recipient_address__c', 'recipient_phone__c', 'recipient_email__c', 'delivery_instructions__c'
    };

    // S2, T2: the AC-006.1 entered fields RutaCargo_Customer may write on create.
    private static final Set<String> CREATEABLE_CUSTOM_FIELDS = new Set<String>{
        'pickup_address__c', 'origin_city__c', 'pickup_postal_code__c', 'pickup_date__c',
        'recipient_name__c', 'recipient_address__c', 'destination_city__c', 'destination_postal_code__c',
        'recipient_phone__c', 'recipient_email__c', 'service_type__c', 'weight_kg__c',
        'package_description__c', 'declared_value__c', 'customer_reference__c', 'delivery_instructions__c'
    };

    @TestSetup
    static void setupShipments() {
        List<Shipment__c> shipments = new List<Shipment__c>();
        shipments.addAll(TestDataFactory.newShipments(accountIdOf(TestDataFactory.SEEDED_CUSTOMER_EMAIL), SHIPMENTS_PER_ACCOUNT));
        shipments.addAll(TestDataFactory.newShipments(accountIdOf(TestDataFactory.SECOND_SEEDED_CUSTOMER_EMAIL), SHIPMENTS_PER_ACCOUNT));
        TestDataFactory.insertShipmentsWithCodes(shipments);
    }

    // ─── Record access through the sharing set (AC-006.7, AC-007.1) ─────────

    @IsTest
    static void anaReadsEveryShipmentOfHerAccount() {
        // AC-006.7 / AC-007.1: customer A (Ana López) reads her own account's shipments.
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
    static void customerReadsExactlyTheAc007FieldsAndTheEnteredRecipientFields() {
        // AC-006.7 (BR-03, P4, G7): read FLS on exactly the AC-007 list and detail
        // fields plus the 4 recipient fields their create FLS makes readable;
        // nothing on cost, margin, notes, hash or Proof_Id__c.
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
        // AC-006.7 (X6): create FLS on exactly the AC-006.1 entered fields; never
        // on price, status, estimate, cost, notes, hash, proof or the last update
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
            'RutaCargo_Customer must make exactly the AC-006.1 custom fields createable on Shipment__c');
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
            SELECT Id FROM Shipment__c WHERE Account__c = :accountId WITH SYSTEM_MODE
        ]).keySet();
    }

    private static Id accountIdOf(String email) {
        Id userId = TestDataFactory.seededCustomerUser(email).Id;
        return [SELECT AccountId FROM User WHERE Id = :userId WITH SYSTEM_MODE].AccountId;
    }
}
