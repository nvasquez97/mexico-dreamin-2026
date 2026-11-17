/**
 * @description Shared test data builders for RutaCargo. Builders return UNSAVED
 *              records with every required field set, so each test decides when
 *              to insert and which fields to override.
 */
@IsTest
public with sharing class TestDataFactory {

    public static final String DEFAULT_ACCOUNT_NAME = 'Test Customer';

    // ─── Accounts (customers) ─────────────────────────────────────────────

    public static Account newCustomerAccount(String name) {
        return new Account(
            Name = name,
            Customer_Type__c = 'Business',
            Credit_Limit__c = 100000,
            Credit_Risk__c = 'Low'
        );
    }

    public static Account newCustomerAccount() {
        return newCustomerAccount(DEFAULT_ACCOUNT_NAME);
    }

    // ─── Shipments ────────────────────────────────────────────────────────

    /**
     * @description Unsaved shipment for the given customer. Status__c is left
     *              empty on purpose so the field default applies on insert.
     */
    public static Shipment__c newShipment(Id accountId) {
        return new Shipment__c(
            Account__c = accountId,
            Service_Type__c = 'Standard',
            Pickup_Address__c = 'Av. Reforma 100, Col. Juarez',
            Pickup_Postal_Code__c = '06600',
            Pickup_Date__c = Date.newInstance(2026, 12, 1),
            Origin_City__c = 'Ciudad de Mexico',
            Destination_City__c = 'Guadalajara',
            Recipient_Name__c = 'Test Recipient',
            Recipient_Address__c = 'Av. Vallarta 200, Col. Americana',
            Destination_Postal_Code__c = '44160',
            Recipient_Phone__c = '+52 33 0000 0000',
            Recipient_Email__c = 'recipient@example.com',
            Package_Description__c = 'Test package',
            Weight_Kg__c = 1.5
        );
    }

    public static List<Shipment__c> newShipments(Id accountId, Integer count) {
        List<Shipment__c> shipments = new List<Shipment__c>();
        for (Integer i = 0; i < count; i++) {
            shipments.add(newShipment(accountId));
        }
        return shipments;
    }
}
