/**
 * @description Response of PublicTrackingController.search (req-001 S1). Holds
 *              only the public information of a shipment (BR-01): no record Id,
 *              no SObject, no private field (BR-03). Dates are strings already
 *              formatted for Mexico City (BR-06).
 */
public with sharing class PublicTrackingResult {

    /** @description The found shipments, at most 50, ordered by tracking number. */
    @AuraEnabled
    public List<TrackedShipment> results = new List<TrackedShipment>();

    /**
     * @description The searched values with no match, in input order, as first
     *              typed (trimmed). Empty when truncated is true.
     */
    @AuraEnabled
    public List<String> notFound = new List<String>();

    /** @description True when more than 50 shipments matched; only the first 50 are returned. */
    @AuraEnabled
    public Boolean truncated = false;

    /**
     * @description The BR-01 fields of one shipment, and nothing else.
     */
    public with sharing class TrackedShipment {
        /** @description Tracking number (Name). */
        @AuraEnabled
        public String trackingNumber;
        /** @description Status__c. */
        @AuraEnabled
        public String status;
        /** @description Origin_City__c. */
        @AuraEnabled
        public String originCity;
        /** @description Destination_City__c. */
        @AuraEnabled
        public String destinationCity;
        /** @description Last_Location__c. */
        @AuraEnabled
        public String lastLocation;
        /** @description Last_Update__c as yyyy-MM-dd HH:mm in America/Mexico_City, or null. */
        @AuraEnabled
        public String lastUpdate;
        /** @description Estimated_Delivery__c as ISO yyyy-MM-dd, or null. */
        @AuraEnabled
        public String estimatedDelivery;
    }
}
