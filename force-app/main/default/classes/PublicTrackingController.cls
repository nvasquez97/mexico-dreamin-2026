/**
 * Apex for the PUBLIC pages (guest user): tracking, delivery details, proof of delivery, reschedule.
 *
 * Guest Apex ignores `without sharing` (the guest has no record sharing), so every query and DML here is
 * explicitly SYSTEM_MODE; therefore every query here selects
 * explicit fields and every DTO exposes only what the business rules allow:
 *  - search()  -> only the BR-01 public fields.
 *  - everything else requires the destination postal code (BR-02) and is throttled.
 * Price, cost, margin, notes and credit data are never selected.
 */
public without sharing class PublicTrackingController {
    @TestVisible private static final Integer MAX_VALUES = 10;
    @TestVisible private static final Integer MAX_FAILED = 5;
    @TestVisible private static final Integer LOCK_MINUTES = 15;
    private static final Integer MAX_RESULTS = 200;
    private static final String MISMATCH = 'The details do not match this shipment';

    public class ShipmentSummary {
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String originCity;
        @AuraEnabled public String destinationCity;
        @AuraEnabled public String lastLocation;
        @AuraEnabled public Datetime lastUpdate;
        @AuraEnabled public Date estimatedDelivery;
    }

    public class SearchResult {
        @AuraEnabled public List<ShipmentSummary> found = new List<ShipmentSummary>();
        @AuraEnabled public List<String> notFound = new List<String>();
    }

    public class DeliveryDetails {
        /** Set (and nothing else) when the postal code does not match or the shipment is locked. */
        @AuraEnabled public String error;
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String recipientAddress;
        @AuraEnabled public String recipientPhone;
        @AuraEnabled public Date estimatedDelivery;
        @AuraEnabled public String deliveryInstructions;
        @AuraEnabled public Boolean delivered;
        @AuraEnabled public Boolean canReschedule;
        @AuraEnabled public String rescheduleBlockedReason;
        @AuraEnabled public Integer reschedulesLeft;
        @AuraEnabled public Date minRescheduleDate;
        @AuraEnabled public Date maxRescheduleDate;
    }

    public class ProofFile {
        @AuraEnabled public String error;
        @AuraEnabled public String fileName;
        @AuraEnabled public String signedBy;
        @AuraEnabled public String pdfBase64;
    }

    // ---------------------------------------------------------------- REQ-001
    /**
     * @param mode   'tracking' or 'reference' (AC-001.1)
     * @param values up to 10 values separated by commas or line breaks
     */
    @AuraEnabled
    public static SearchResult search(String mode, String values) {
        if (mode != 'tracking' && mode != 'reference') {
            throw ShipmentRules.userError('Choose to search by tracking number or by order reference.');
        }
        // AC-001.5: trim, ignore case; de-duplicate; drop empties
        List<String> requested = new List<String>();
        Set<String> seen = new Set<String>();
        for (String raw : (values == null ? '' : values).split('[,\\r\\n]+')) {
            String v = raw.trim();
            if (v.length() > 0 && seen.add(v.toLowerCase())) {
                requested.add(v);
            }
        }
        if (requested.isEmpty()) {
            throw ShipmentRules.userError('Enter at least one value.');
        }
        if (requested.size() > MAX_VALUES) {
            throw ShipmentRules.userError('You can look up at most ' + MAX_VALUES + ' values at a time.');
        }

        List<Shipment__c> rows;
        if (mode == 'tracking') {
            rows = [
                SELECT Name, Status__c, Origin_City__c, Destination_City__c, Last_Location__c, Last_Update__c,
                       Estimated_Delivery__c, Customer_Reference__c
                FROM Shipment__c WHERE Name IN :requested WITH SYSTEM_MODE LIMIT :MAX_RESULTS
            ];
        } else {
            rows = [
                SELECT Name, Status__c, Origin_City__c, Destination_City__c, Last_Location__c, Last_Update__c,
                       Estimated_Delivery__c, Customer_Reference__c
                FROM Shipment__c WHERE Customer_Reference__c IN :requested WITH SYSTEM_MODE LIMIT :MAX_RESULTS
            ];
        }

        SearchResult result = new SearchResult();
        Set<String> matched = new Set<String>();
        for (Shipment__c s : rows) {
            String key = (mode == 'tracking' ? s.Name : s.Customer_Reference__c).toLowerCase();
            matched.add(key);
            result.found.add(toSummary(s));
        }
        for (String v : requested) {
            if (!matched.contains(v.toLowerCase())) {
                result.notFound.add(v); // AC-001.3
            }
        }
        return result;
    }

    // ---------------------------------------------------------------- REQ-002
    @AuraEnabled
    public static DeliveryDetails getDeliveryDetails(String trackingNumber, String postalCode) {
        Verified v = verify(trackingNumber, postalCode, false, true);
        if (v.error != null) {
            DeliveryDetails d = new DeliveryDetails();
            d.error = v.error;
            return d;
        }
        return toDetails(v.shipment);
    }

    @AuraEnabled
    public static ProofFile getProofOfDelivery(String trackingNumber, String postalCode) {
        // No counter reset (DML) before the callout, no row lock during the 10 s callout.
        Verified v = verify(trackingNumber, postalCode, false, false);
        if (v.error != null) {
            ProofFile f = new ProofFile();
            f.error = v.error;
            return f;
        }
        Shipment__c s = v.shipment;
        if (s.Status__c != 'Delivered' || String.isBlank(s.Proof_Id__c)) {
            throw ShipmentRules.userError('The proof of delivery is not available yet.');
        }
        try {
            EntregaYaClient.Proof p = EntregaYaClient.getProof(s.Proof_Id__c);
            // Never hand out a proof that EntregaYa attributes to another shipment.
            if (String.isNotBlank(p.trackingNumber) && !p.trackingNumber.equalsIgnoreCase(s.Name)) {
                throw new EntregaYaClient.ProofException('Proof belongs to another shipment');
            }
            ProofFile f = new ProofFile();
            f.fileName = String.isBlank(p.fileName) ? 'proof-of-delivery.pdf' : p.fileName;
            f.signedBy = p.signedBy;
            f.pdfBase64 = p.pdfBase64;
            return f; // AC-002.4: fetched on demand, never stored in Salesforce
        } catch (EntregaYaClient.ProofException e) {
            System.debug(LoggingLevel.WARN, 'Proof fetch failed for ' + s.Name + ': ' + e.getMessage());
            throw ShipmentRules.userError('We could not get the proof of delivery, please try again later'); // AC-002.5
        }
    }

    // ---------------------------------------------------------------- REQ-003
    @AuraEnabled
    public static DeliveryDetails reschedule(String trackingNumber, String postalCode, Date newDate, String instructions) {
        Verified v = verify(trackingNumber, postalCode, true, true);
        if (v.error != null) {
            DeliveryDetails d = new DeliveryDetails();
            d.error = v.error;
            return d;
        }
        Shipment__c s = v.shipment;
        if (!ShipmentRules.RESCHEDULABLE.contains(s.Status__c)) {
            return failure('Only shipments that are Picked up or In transit can be rescheduled.'); // AC-003.3
        }
        Integer count = s.Reschedule_Count__c == null ? 0 : s.Reschedule_Count__c.intValue();
        if (count >= ShipmentRules.MAX_RESCHEDULES) {
            return failure('This shipment has already been rescheduled ' + ShipmentRules.MAX_RESCHEDULES + ' times.'); // AC-003.4
        }
        if (newDate == null) {
            return failure('Choose a new delivery date.');
        }
        Date minDate = ShipmentRules.today().addDays(1);
        Date original = s.Original_Estimated_Delivery__c != null ? s.Original_Estimated_Delivery__c : s.Estimated_Delivery__c;
        Date maxDate = original == null ? null : original.addDays(7);
        if (maxDate == null || maxDate < minDate) {
            return failure('This delivery can no longer be rescheduled.');
        }
        if (newDate < minDate || newDate > maxDate) { // AC-003.2
            return failure('Choose a date between ' + fmt(minDate) + ' and ' + fmt(maxDate) + '.');
        }
        if (newDate == s.Estimated_Delivery__c) {
            return failure('Choose a date different from the current estimated delivery date.');
        }
        String newInstructions = instructions == null ? '' : instructions.trim();
        if (newInstructions.length() > 2000) {
            return failure('Delivery instructions can have at most 2000 characters.');
        }

        // AC-003.5: audit row keeps who/when (CreatedDate) and before/after values for support agents
        Database.insert(new Shipment_Change__c(
            Shipment__c = s.Id,
            Previous_Date__c = s.Estimated_Delivery__c,
            New_Date__c = newDate,
            Previous_Instructions__c = s.Delivery_Instructions__c,
            New_Instructions__c = newInstructions
        ), AccessLevel.SYSTEM_MODE);
        s.Original_Estimated_Delivery__c = original;
        s.Estimated_Delivery__c = newDate;
        s.Delivery_Instructions__c = newInstructions;
        s.Reschedule_Count__c = count + 1;
        Database.update(s, AccessLevel.SYSTEM_MODE);
        return toDetails(s);
    }

    // ---------------------------------------------------------------- helpers
    private class Verified {
        Shipment__c shipment;
        String error;
    }

    /**
     * Loads a shipment only if the postal code matches (BR-02). Wrong codes are counted and, after
     * MAX_FAILED consecutive failures, the shipment is locked for LOCK_MINUTES to stop guessing.
     * A mismatch is RETURNED, not thrown: an exception would roll back the failure counter.
     */
    private static Verified verify(String trackingNumber, String postalCode, Boolean lockRow, Boolean allowReset) {
        Verified out = new Verified();
        String tn = trackingNumber == null ? '' : trackingNumber.trim();
        String cp = ShipmentRules.normalizePostalCode(postalCode);
        if (tn == '' || cp == '') {
            throw ShipmentRules.userError('Enter the destination postal code.');
        }
        List<Shipment__c> rows = lockRow ? [
            SELECT Id, Name, Status__c, Recipient_Name__c, Recipient_Address__c, Recipient_Phone__c,
                   Estimated_Delivery__c, Original_Estimated_Delivery__c, Delivery_Instructions__c, Reschedule_Count__c,
                   Destination_Postal_Code__c, Proof_Id__c, Failed_Verifications__c, Verification_Locked_Until__c
            FROM Shipment__c WHERE Name = :tn WITH SYSTEM_MODE LIMIT 1 FOR UPDATE
        ] : [
            SELECT Id, Name, Status__c, Recipient_Name__c, Recipient_Address__c, Recipient_Phone__c,
                   Estimated_Delivery__c, Original_Estimated_Delivery__c, Delivery_Instructions__c, Reschedule_Count__c,
                   Destination_Postal_Code__c, Proof_Id__c, Failed_Verifications__c, Verification_Locked_Until__c
            FROM Shipment__c WHERE Name = :tn WITH SYSTEM_MODE LIMIT 1
        ];
        if (rows.isEmpty()) {
            out.error = MISMATCH;
            return out;
        }
        Shipment__c s = rows[0];
        if (s.Verification_Locked_Until__c != null && s.Verification_Locked_Until__c > Datetime.now()) {
            out.error = 'Too many wrong attempts. Please try again in ' + LOCK_MINUTES + ' minutes.';
            return out;
        }
        Integer failedSoFar = s.Failed_Verifications__c == null ? 0 : s.Failed_Verifications__c.intValue();
        if (String.isBlank(s.Destination_Postal_Code__c) || s.Destination_Postal_Code__c.trim() != cp) {
            // Always counted (a callout never follows a mismatch, so DML is safe here).
            Integer failed = failedSoFar + 1;
            Database.update(new Shipment__c(
                Id = s.Id,
                Failed_Verifications__c = failed >= MAX_FAILED ? 0 : failed,
                Verification_Locked_Until__c = failed >= MAX_FAILED ? Datetime.now().addMinutes(LOCK_MINUTES) : null
            ), AccessLevel.SYSTEM_MODE);
            out.error = MISMATCH; // AC-002.3
            return out;
        }
        if (allowReset && failedSoFar > 0) {
            Database.update(new Shipment__c(Id = s.Id, Failed_Verifications__c = 0, Verification_Locked_Until__c = null), AccessLevel.SYSTEM_MODE);
        }
        out.shipment = s;
        return out;
    }

    private static DeliveryDetails failure(String message) {
        DeliveryDetails d = new DeliveryDetails();
        d.error = message;
        return d;
    }

    private static ShipmentSummary toSummary(Shipment__c s) {
        ShipmentSummary r = new ShipmentSummary();
        r.trackingNumber = s.Name;
        r.status = s.Status__c;
        r.originCity = s.Origin_City__c;
        r.destinationCity = s.Destination_City__c;
        r.lastLocation = s.Last_Location__c;
        r.lastUpdate = s.Last_Update__c;
        r.estimatedDelivery = s.Estimated_Delivery__c;
        return r;
    }

    private static DeliveryDetails toDetails(Shipment__c s) {
        DeliveryDetails d = new DeliveryDetails();
        d.trackingNumber = s.Name;
        d.status = s.Status__c;
        d.recipientName = s.Recipient_Name__c;
        d.recipientAddress = s.Recipient_Address__c;
        d.recipientPhone = s.Recipient_Phone__c;
        d.estimatedDelivery = s.Estimated_Delivery__c;
        d.deliveryInstructions = s.Delivery_Instructions__c;
        d.delivered = s.Status__c == 'Delivered';
        Integer count = s.Reschedule_Count__c == null ? 0 : s.Reschedule_Count__c.intValue();
        d.reschedulesLeft = Math.max(0, ShipmentRules.MAX_RESCHEDULES - count);
        Date original = s.Original_Estimated_Delivery__c != null ? s.Original_Estimated_Delivery__c : s.Estimated_Delivery__c;
        d.minRescheduleDate = ShipmentRules.today().addDays(1);
        d.maxRescheduleDate = original == null ? null : original.addDays(7);
        d.canReschedule = true;
        if (!ShipmentRules.RESCHEDULABLE.contains(s.Status__c)) {
            d.canReschedule = false;
            d.rescheduleBlockedReason = 'Only shipments that are Picked up or In transit can be rescheduled.';
        } else if (d.reschedulesLeft == 0) {
            d.canReschedule = false;
            d.rescheduleBlockedReason = 'This shipment has already been rescheduled ' + ShipmentRules.MAX_RESCHEDULES + ' times.';
        } else if (d.maxRescheduleDate == null || d.maxRescheduleDate < d.minRescheduleDate) {
            d.canReschedule = false;
            d.rescheduleBlockedReason = 'This delivery can no longer be rescheduled.';
        }
        return d;
    }

    private static String fmt(Date d) {
        return Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format('MMM d, yyyy');
    }
}
