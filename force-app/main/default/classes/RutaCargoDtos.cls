/**
 * Data transfer objects returned to the site. Each DTO lists only the fields its audience may see:
 * TrackedShipment is the public view (BR-01); DeliveryDetails is recipient-only (BR-02);
 * MyShipment and ShipmentDetail are customer-only (BR-03, BR-07). Internal fields (carrier cost,
 * margin, internal notes, credit data) never appear in any DTO (BR-03).
 */
public inherited sharing class RutaCargoDtos {
    public static final String OK = 'OK';
    public static final String MISMATCH = 'MISMATCH';
    public static final String LOCKED = 'LOCKED';
    public static final String REJECTED = 'REJECTED';
    public static final String UNAVAILABLE = 'UNAVAILABLE';

    /** Public tracking row (AC-001.2). */
    public class TrackedShipment {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String originCity;
        @AuraEnabled public String destinationCity;
        @AuraEnabled public String lastLocation;
        @AuraEnabled public Datetime lastUpdate;
        @AuraEnabled public Date estimatedDelivery;
    }

    /** Result of a public tracking search. */
    public class TrackingResponse {
        @AuraEnabled public List<TrackedShipment> found = new List<TrackedShipment>();
        @AuraEnabled public List<String> notFound = new List<String>();
    }

    /** Recipient view after the postal code was verified (AC-002.2). */
    public class DeliveryDetails {
        @AuraEnabled public String outcome;
        @AuraEnabled public String message;
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String recipientAddress;
        @AuraEnabled public String recipientPhone;
        @AuraEnabled public Date estimatedDelivery;
        @AuraEnabled public String deliveryInstructions;
        @AuraEnabled public Integer rescheduleCount;
        @AuraEnabled public Boolean canReschedule;
        @AuraEnabled public Date earliestRescheduleDate;
        @AuraEnabled public Date latestRescheduleDate;
        @AuraEnabled public Boolean hasProof;
    }

    /** Proof of delivery, streamed from EntregaYa and never stored (AC-002.4). */
    public class ProofResult {
        @AuraEnabled public String outcome;
        @AuraEnabled public String message;
        @AuraEnabled public String fileName;
        @AuraEnabled public String pdfBase64;
    }

    /** Generic action outcome. */
    public class ActionResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public Decimal price;
        @AuraEnabled public Date estimatedDelivery;
    }

    /** Row of "my shipments" (AC-007.1). */
    public class MyShipment {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public Date requestedOn;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String destinationCity;
        @AuraEnabled public String status;
        @AuraEnabled public String serviceType;
        @AuraEnabled public Decimal price;
        @AuraEnabled public String customerReference;
    }

    /** Customer-only shipment detail (AC-007.3). */
    public class ShipmentDetail {
        @AuraEnabled public MyShipment summary;
        @AuraEnabled public String pickupAddress;
        @AuraEnabled public String pickupPostalCode;
        @AuraEnabled public Date pickupDate;
        @AuraEnabled public String originCity;
        @AuraEnabled public String recipientAddress;
        @AuraEnabled public String destinationPostalCode;
        @AuraEnabled public String recipientPhone;
        @AuraEnabled public String recipientEmail;
        @AuraEnabled public String deliveryInstructions;
        @AuraEnabled public String packageDescription;
        @AuraEnabled public Decimal weightKg;
        @AuraEnabled public Decimal declaredValue;
        @AuraEnabled public Date estimatedDelivery;
    }
}
