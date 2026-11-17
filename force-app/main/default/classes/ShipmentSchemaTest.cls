/**
 * @description Proves the foundation data model of RutaCargo: Account customer
 *              fields, the Shipment__c object and its fields, the tracking-number
 *              auto number, the margin formula, the status default, field history
 *              and the sharing models.
 *              Covers AC-F.1, AC-F.2, AC-F.3, AC-F.12 and AC-F.6 of
 *              odd/tasks/foundation.md.
 */
@IsTest
private with sharing class ShipmentSchemaTest {

    private static final Pattern TRACKING_NUMBER = Pattern.compile('^RC(\\d{9})$');

    // SECURITY-JUSTIFICATION: this class proves the data model (types, defaults,
    // formula, auto number), not access. At API 67 DML and SOQL default to user
    // mode and field permissions are granted by the permission sets of task T3,
    // so test-only DML and SOQL here run in system mode. Scope: this test class
    // only. Compensating control: access is proven with System.runAs in
    // SupportAgentAccessTest (T3). (task-reviewer T1, 2026-11-17)
    private static void insertAsSystem(List<SObject> records) {
        Database.insert(records, AccessLevel.SYSTEM_MODE);
    }

    @TestSetup
    static void setup() {
        insertAsSystem(new List<Account>{ TestDataFactory.newCustomerAccount() });
    }

    private static Id customerId() {
        return [SELECT Id FROM Account WHERE Name = :TestDataFactory.DEFAULT_ACCOUNT_NAME WITH SYSTEM_MODE LIMIT 1].Id;
    }

    private static List<String> picklistValues(Schema.SObjectField field) {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            Assert.areEqual(entry.getLabel(), entry.getValue(),
                'Picklist API name must equal its label: ' + entry.getValue());
            values.add(entry.getValue());
        }
        return values;
    }

    // ─── AC-F.1 (data model) ──────────────────────────────────────────────

    @IsTest
    static void statusPicklist_hasExactlyTheSixDesignValues() {
        // AC-F.1: Status__c has exactly Requested, Picked up, In transit,
        // Out for delivery, Delivered, Exception (API name = label)
        List<String> expected = new List<String>{
            'Requested', 'Picked up', 'In transit', 'Out for delivery', 'Delivered', 'Exception'
        };
        Assert.areEqual(expected, picklistValues(Shipment__c.Status__c),
            'Status__c must have exactly the six design values in order');
    }

    @IsTest
    static void serviceTypePicklist_hasStandardAndExpress() {
        // AC-F.1: Service_Type__c has Standard and Express
        Assert.areEqual(new List<String>{ 'Standard', 'Express' },
            picklistValues(Shipment__c.Service_Type__c),
            'Service_Type__c must have exactly Standard and Express');
    }

    @IsTest
    static void customerTypePicklist_hasIndividualAndBusiness() {
        // AC-F.1: Customer_Type__c has Individual and Business
        Assert.areEqual(new List<String>{ 'Individual', 'Business' },
            picklistValues(Account.Customer_Type__c),
            'Customer_Type__c must have exactly Individual and Business');
    }

    @IsTest
    static void creditRiskPicklist_hasLowMediumAndHigh() {
        // AC-F.1: Credit_Risk__c has Low, Medium and High
        Assert.areEqual(new List<String>{ 'Low', 'Medium', 'High' },
            picklistValues(Account.Credit_Risk__c),
            'Credit_Risk__c must have exactly Low, Medium and High');
    }

    @IsTest
    static void customerReference_isNonUniqueExternalId() {
        // AC-F.1: Customer_Reference__c is an External ID (decided: not unique)
        Schema.DescribeFieldResult field = Shipment__c.Customer_Reference__c.getDescribe();
        Assert.isTrue(field.isExternalId(), 'Customer_Reference__c must be an External ID');
        Assert.isFalse(field.isUnique(), 'Customer_Reference__c must not be unique');
    }

    @IsTest
    static void accountLookup_isRequiredWithRestrictDelete() {
        // AC-F.1: Account__c is required (lookup to Account, delete Restrict)
        Schema.DescribeFieldResult field = Shipment__c.Account__c.getDescribe();
        Assert.areEqual(Schema.DisplayType.REFERENCE, field.getType(), 'Account__c must be a lookup');
        Assert.areEqual(Account.SObjectType, field.getReferenceTo()[0], 'Account__c must point to Account');
        Assert.isFalse(field.isNillable(), 'Account__c must be required');
        Assert.isTrue(field.isRestrictedDelete(), 'Deleting an Account with shipments must be restricted');
    }

    @IsTest
    static void everyDesignField_existsWithItsType() {
        // AC-F.1: every field of the design table exists with its type
        Map<String, Schema.DisplayType> expected = new Map<String, Schema.DisplayType>{
            'name' => Schema.DisplayType.STRING,
            'account__c' => Schema.DisplayType.REFERENCE,
            'customer_reference__c' => Schema.DisplayType.STRING,
            'status__c' => Schema.DisplayType.PICKLIST,
            'service_type__c' => Schema.DisplayType.PICKLIST,
            'pickup_address__c' => Schema.DisplayType.TEXTAREA,
            'pickup_postal_code__c' => Schema.DisplayType.STRING,
            'pickup_date__c' => Schema.DisplayType.DATE,
            'origin_city__c' => Schema.DisplayType.STRING,
            'destination_city__c' => Schema.DisplayType.STRING,
            'recipient_name__c' => Schema.DisplayType.STRING,
            'recipient_address__c' => Schema.DisplayType.TEXTAREA,
            'destination_postal_code__c' => Schema.DisplayType.STRING,
            'recipient_phone__c' => Schema.DisplayType.PHONE,
            'recipient_email__c' => Schema.DisplayType.EMAIL,
            'delivery_instructions__c' => Schema.DisplayType.TEXTAREA,
            'package_description__c' => Schema.DisplayType.STRING,
            'weight_kg__c' => Schema.DisplayType.DOUBLE,
            'declared_value__c' => Schema.DisplayType.CURRENCY,
            'price__c' => Schema.DisplayType.CURRENCY,
            'estimated_delivery__c' => Schema.DisplayType.DATE,
            'original_estimated_delivery__c' => Schema.DisplayType.DATE,
            'reschedule_count__c' => Schema.DisplayType.DOUBLE,
            'last_location__c' => Schema.DisplayType.STRING,
            'last_update__c' => Schema.DisplayType.DATETIME,
            'delivered_at__c' => Schema.DisplayType.DATETIME,
            'proof_id__c' => Schema.DisplayType.STRING,
            'carrier_cost__c' => Schema.DisplayType.CURRENCY,
            'margin__c' => Schema.DisplayType.PERCENT,
            'internal_notes__c' => Schema.DisplayType.TEXTAREA,
            'delivery_access_code_hash__c' => Schema.DisplayType.STRING
        };
        Map<String, Schema.SObjectField> actual = Schema.SObjectType.Shipment__c.fields.getMap();
        for (String fieldName : expected.keySet()) {
            Assert.isTrue(actual.containsKey(fieldName), 'Shipment__c is missing field ' + fieldName);
            Assert.areEqual(expected.get(fieldName), actual.get(fieldName).getDescribe().getType(),
                'Wrong type for Shipment__c.' + fieldName);
        }
        Assert.isTrue(Shipment__c.Name.getDescribe().isAutoNumber(), 'Name must be an Auto Number');
        Assert.isTrue(Shipment__c.Margin__c.getDescribe().isCalculated(), 'Margin__c must be a formula');
        Assert.areEqual(100, Shipment__c.Delivery_Access_Code_Hash__c.getDescribe().getLength(),
            'Delivery_Access_Code_Hash__c must be Text(100)');

        Map<String, Schema.SObjectField> account = Schema.SObjectType.Account.fields.getMap();
        Assert.areEqual(Schema.DisplayType.PICKLIST, account.get('customer_type__c').getDescribe().getType(),
            'Account.Customer_Type__c must be a picklist');
        Assert.areEqual(Schema.DisplayType.CURRENCY, account.get('credit_limit__c').getDescribe().getType(),
            'Account.Credit_Limit__c must be a currency');
        Assert.areEqual(Schema.DisplayType.PICKLIST, account.get('credit_risk__c').getDescribe().getType(),
            'Account.Credit_Risk__c must be a picklist');
    }

    // ─── AC-F.2 (BR-05) ───────────────────────────────────────────────────

    @IsTest
    static void trackingNumbers_areConsecutiveRcNineDigits() {
        // AC-F.2: two shipments inserted one after the other get Names matching
        // ^RC\d{9}$ and the second number is the first plus 1
        Id accountId = customerId();
        Shipment__c first = TestDataFactory.newShipment(accountId);
        Shipment__c second = TestDataFactory.newShipment(accountId);

        Test.startTest();
        insertAsSystem(new List<Shipment__c>{ first });
        insertAsSystem(new List<Shipment__c>{ second });
        Test.stopTest();

        Map<Id, Shipment__c> saved = new Map<Id, Shipment__c>(
            [SELECT Id, Name FROM Shipment__c WHERE Id IN :new List<Id>{ first.Id, second.Id } WITH SYSTEM_MODE]
        );
        Matcher firstName = TRACKING_NUMBER.matcher(saved.get(first.Id).Name);
        Matcher secondName = TRACKING_NUMBER.matcher(saved.get(second.Id).Name);
        Assert.isTrue(firstName.matches(), 'First tracking number must match ^RC\\d{9}$: ' + saved.get(first.Id).Name);
        Assert.isTrue(secondName.matches(), 'Second tracking number must match ^RC\\d{9}$: ' + saved.get(second.Id).Name);
        Assert.areEqual(Long.valueOf(firstName.group(1)) + 1, Long.valueOf(secondName.group(1)),
            'The second tracking number must be the first plus 1');
    }

    // ─── AC-F.3 (BR-03, data model) ───────────────────────────────────────

    private static Decimal marginFor(Decimal price, Decimal carrierCost) {
        Shipment__c shipment = TestDataFactory.newShipment(customerId());
        shipment.Price__c = price;
        shipment.Carrier_Cost__c = carrierCost;
        Test.startTest();
        insertAsSystem(new List<Shipment__c>{ shipment });
        Test.stopTest();
        return [SELECT Margin__c FROM Shipment__c WHERE Id = :shipment.Id WITH SYSTEM_MODE].Margin__c;
    }

    @IsTest
    static void margin_is25Percent_whenPrice200AndCost150() {
        // AC-F.3: Price__c 200 and Carrier_Cost__c 150 -> Margin__c 25%
        Assert.areEqual(25.00, marginFor(200, 150), 'Margin must be (200 - 150) / 200 = 25%');
    }

    @IsTest
    static void margin_is75Percent_whenPrice400AndCost100() {
        // AC-F.3: Price__c 400 and Carrier_Cost__c 100 -> Margin__c 75%
        Assert.areEqual(75.00, marginFor(400, 100), 'Margin must be (400 - 100) / 400 = 75%');
    }

    @IsTest
    static void margin_isEmpty_whenPriceIsZero() {
        // AC-F.3: Price__c 0 -> Margin__c empty
        Assert.isNull(marginFor(0, 150), 'Margin must be empty when the price is 0');
    }

    @IsTest
    static void margin_isEmpty_whenPriceIsEmpty() {
        // AC-F.3: Price__c empty -> Margin__c empty
        Assert.isNull(marginFor(null, 150), 'Margin must be empty when the price is empty');
    }

    // ─── AC-F.12 (BR-09) ──────────────────────────────────────────────────

    @IsTest
    static void status_defaultsToRequested_whenInsertedWithoutStatus() {
        // AC-F.12: a shipment inserted without a status is Requested
        // (251 records, across the 200-record batch boundary)
        List<Shipment__c> shipments = TestDataFactory.newShipments(customerId(), 251);

        Test.startTest();
        insertAsSystem(shipments);
        Test.stopTest();

        List<Shipment__c> saved = [SELECT Status__c FROM Shipment__c WITH SYSTEM_MODE];
        Assert.areEqual(251, saved.size(), 'All 251 shipments must be saved');
        for (Shipment__c shipment : saved) {
            Assert.areEqual('Requested', shipment.Status__c, 'A shipment without status must default to Requested');
        }
    }

    // ─── AC-F.6 (AC-003.5 support, P3) ────────────────────────────────────
    // Field history (IsFieldHistoryTracked) and the Apex settings are proven by
    // the Tooling queries recorded in odd/evidence/foundation/T1.md: Apex only
    // sees FieldDefinition rows of fields the running user has FLS on, and the
    // field permissions arrive with task T3.

    @IsTest
    static void sharingModels_arePrivateForShipmentAndAccount() {
        // AC-F.6: Shipment__c and Account internal and external sharing are Private
        Map<String, EntityDefinition> entities = new Map<String, EntityDefinition>();
        for (EntityDefinition entity : [
            SELECT QualifiedApiName, InternalSharingModel, ExternalSharingModel
            FROM EntityDefinition
            WHERE QualifiedApiName IN ('Shipment__c', 'Account')
        ]) {
            entities.put(entity.QualifiedApiName, entity);
        }
        for (String objectName : new List<String>{ 'Shipment__c', 'Account' }) {
            Assert.areEqual('Private', entities.get(objectName).InternalSharingModel,
                objectName + ' internal sharing must be Private');
            Assert.areEqual('Private', entities.get(objectName).ExternalSharingModel,
                objectName + ' external sharing must be Private');
        }
    }
}
