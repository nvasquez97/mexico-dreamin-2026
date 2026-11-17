/**
 * @description One EntregaYa status change, as individual fields (req-004 S1,
 *              policy X6: never an SObject). EntregaYaStatusResource (T3) parses
 *              the JSON body into it; EntregaYaStatusService validates every field
 *              before anything is read or written.
 */
public with sharing class EntregaYaStatusRequest {
    /** @description Tracking number, the shipment Name: RC followed by 9 digits. */
    public String trackingNumber;
    /** @description One of the six Status__c values, exact case. */
    public String status;
    /** @description Free-text location, 1 to 255 characters after trimming. */
    public String location;
    /** @description ISO-8601 date and time with a mandatory offset (Z or +hh:mm / -hh:mm). */
    public String timestamp;
    /** @description Proof of delivery id; required only when status is Delivered. */
    public String proofId;
}
