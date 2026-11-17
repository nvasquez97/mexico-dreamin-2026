/**
 * @description Reads the public (BR-01) fields of shipments for
 *              PublicTrackingController, the guest tracking search (req-001 S1).
 *              One static, bound query per search mode; no dynamic SOQL.
 */
// SECURITY-JUSTIFICATION: why: the site guest user has no object permission
// and no sharing on Shipment__c (Private, foundation S1/A2, project rule "the
// guest receives no object permissions"), yet BR-01 makes the tracking fields
// public to anyone holding a tracking number or an order reference. Scope: only
// these two read-only queries, selecting Name, Customer_Reference__c and the
// BR-01 fields, filtered by bound values, at most 51 rows; no DML, no other
// object. Compensating control: the only caller is PublicTrackingController
// (with sharing), which validates the mode against a closed list, caps the
// values at 10 and their length at 50, and returns a DTO with the seven BR-01
// properties only (no Id, no SObject). (pending owner approval, 2026-11-17)
public without sharing class PublicTrackingSelector {

    /** @description Rows read per search: 50 returned, the 51st proves the cap was hit. */
    @TestVisible
    private static final Integer ROW_LIMIT = 51;

    /**
     * @description Shipments whose tracking number (Name) is one of the given
     *              values. SOQL compares text case-insensitively.
     * @param trackingNumbers the tracking numbers to look for
     * @return at most 51 shipments, ordered by Name
     */
    public static List<Shipment__c> selectByTrackingNumbers(Set<String> trackingNumbers) {
        return [
            SELECT Name, Customer_Reference__c, Status__c, Origin_City__c, Destination_City__c,
                Last_Location__c, Last_Update__c, Estimated_Delivery__c
            FROM Shipment__c
            WHERE Name IN :trackingNumbers
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT :ROW_LIMIT
        ];
    }

    /**
     * @description Shipments whose Customer_Reference__c is one of the given
     *              values. SOQL compares text case-insensitively.
     * @param references the order references to look for
     * @return at most 51 shipments, ordered by Name
     */
    public static List<Shipment__c> selectByReferences(Set<String> references) {
        return [
            SELECT Name, Customer_Reference__c, Status__c, Origin_City__c, Destination_City__c,
                Last_Location__c, Last_Update__c, Estimated_Delivery__c
            FROM Shipment__c
            WHERE Customer_Reference__c IN :references
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT :ROW_LIMIT
        ];
    }
}
