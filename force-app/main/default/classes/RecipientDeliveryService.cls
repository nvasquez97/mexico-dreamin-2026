/**
 * REQ-002 / REQ-003 — delivery details, proof of delivery and rescheduling for the recipient.
 *
 * BR-02: the recipient's personal data, the proof of delivery and changes to the delivery are
 * exclusive to the recipient. Recipients have no login, so every call re-verifies the
 * destination postal code (AC-002.1) on the server; nothing is trusted from a previous call.
 * Repeated wrong postal codes lock the shipment for a while, so the 5-digit code cannot be
 * brute-forced from the public site.
 *
 * Runs WITHOUT SHARING because the callers are guest users with no object access; this class
 * is the access control.
 */
public without sharing class RecipientDeliveryService {
  public static final String MSG_NOT_FOUND = 'We could not find a shipment with that tracking number.';
  public static final String MSG_MISMATCH = 'The details do not match this shipment';
  public static final String MSG_LOCKED = 'Too many attempts. Please try again in a few minutes.';
  public static final String MSG_PROOF_UNAVAILABLE = 'We could not get the proof of delivery, please try again later';
  public static final String MSG_PROOF_NOT_READY = 'The proof of delivery is available once the shipment is Delivered.';

  public class RecipientException extends Exception {
  }

  public class DeliveryDetails {
    @AuraEnabled
    public String trackingNumber;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String recipientName;
    @AuraEnabled
    public String deliveryAddress;
    @AuraEnabled
    public String destinationCity;
    @AuraEnabled
    public String destinationPostalCode;
    @AuraEnabled
    public String contactPhone;
    @AuraEnabled
    public Date estimatedDelivery;
    @AuraEnabled
    public String deliveryInstructions;
    @AuraEnabled
    public Datetime deliveredAt;
    @AuraEnabled
    public Boolean canDownloadProof;
    @AuraEnabled
    public Boolean canReschedule;
    @AuraEnabled
    public String rescheduleBlockedReason;
    @AuraEnabled
    public Date rescheduleMinDate;
    @AuraEnabled
    public Date rescheduleMaxDate;
    @AuraEnabled
    public Integer reschedulesLeft;
  }

  public class Result {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public DeliveryDetails details;
  }

  public class ProofResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String fileName;
    @AuraEnabled
    public String signedBy;
    @AuraEnabled
    public String pdfBase64;
  }

  // ---------------------------------------------------------------- REQ-002

  public static Result getDetails(String trackingNumber, String postalCode) {
    Shipment__c shipment = find(trackingNumber, false);
    String failure = verify(shipment, postalCode, true);
    return failure != null ? failure(failure) : success(shipment);
  }

  /** AC-002.4 / AC-002.5. The PDF is passed through to the browser and never stored. */
  public static ProofResult getProof(String trackingNumber, String postalCode) {
    ProofResult result = new ProofResult();
    result.success = false;
    Shipment__c shipment = find(trackingNumber, false);
    // No DML may happen before the callout; failures are recorded only on mismatch.
    String failure = verify(shipment, postalCode, false);
    if (failure != null) {
      result.message = failure;
      return result;
    }
    if (
      shipment.Status__c != ShipmentConstants.STATUS_DELIVERED ||
      String.isBlank(shipment.Proof_Id__c)
    ) {
      result.message = MSG_PROOF_NOT_READY;
      return result;
    }
    try {
      EntregaYaProofClient.ProofOfDelivery proof = EntregaYaProofClient.getProof(
        shipment.Proof_Id__c
      );
      if (
        String.isNotBlank(proof.trackingNumber) &&
        !proof.trackingNumber.equalsIgnoreCase(shipment.Name)
      ) {
        throw new EntregaYaProofClient.EntregaYaException(
          'Proof belongs to another shipment'
        );
      }
      result.success = true;
      result.fileName = String.isBlank(proof.fileName)
        ? shipment.Name + '-proof-of-delivery.pdf'
        : proof.fileName;
      result.signedBy = proof.signedBy;
      result.pdfBase64 = proof.pdfBase64;
    } catch (EntregaYaProofClient.EntregaYaException e) {
      System.debug(
        LoggingLevel.ERROR,
        'EntregaYa proof ' + shipment.Proof_Id__c + ': ' + e.getMessage()
      );
      result.message = MSG_PROOF_UNAVAILABLE;
    }
    resetFailures(shipment);
    return result;
  }

  // ---------------------------------------------------------------- REQ-003

  public static Result reschedule(
    String trackingNumber,
    String postalCode,
    Date newDate,
    String instructions
  ) {
    Shipment__c shipment = find(trackingNumber, true);
    String failure = verify(shipment, postalCode, true);
    if (failure != null) {
      return failure(failure);
    }
    String blocked = rescheduleBlockedReason(shipment);
    if (blocked != null) {
      return failure(blocked);
    }
    Date minDate = rescheduleMinDate();
    Date maxDate = rescheduleMaxDate(shipment);
    if (newDate == null || newDate < minDate || newDate > maxDate) {
      return failure(
        'Choose a date between ' +
          RutaCargoDates.format(minDate) +
          ' and ' +
          RutaCargoDates.format(maxDate) +
          '.'
      );
    }
    String cleanInstructions = instructions == null
      ? null
      : instructions.trim();
    if (cleanInstructions != null && cleanInstructions.length() > 1000) {
      return failure('Delivery instructions can have up to 1,000 characters.');
    }
    // The original estimate bounds the window (AC-003.2) even after a first reschedule.
    if (shipment.Original_Estimated_Delivery__c == null) {
      shipment.Original_Estimated_Delivery__c = shipment.Estimated_Delivery__c;
    }
    shipment.Estimated_Delivery__c = newDate;
    shipment.Delivery_Instructions__c = cleanInstructions;
    shipment.Reschedule_Count__c = rescheduleCount(shipment) + 1;
    // AC-003.5: field history on these fields records when each change was made.
    Database.update(shipment, AccessLevel.SYSTEM_MODE);
    Result result = success(shipment);
    result.message =
      'Your delivery is now scheduled for ' +
      RutaCargoDates.format(newDate) +
      '.';
    return result;
  }

  // ---------------------------------------------------------------- helpers

  private static Shipment__c find(String trackingNumber, Boolean forUpdate) {
    String key = trackingNumber == null
      ? ''
      : trackingNumber.trim().toUpperCase();
    if (!ShipmentConstants.TRACKING_NUMBER_PATTERN.matcher(key).matches()) {
      return null;
    }
    List<Shipment__c> rows = forUpdate
      ? [
          SELECT
            Id,
            Name,
            Status__c,
            Recipient_Name__c,
            Recipient_Address__c,
            Destination_City__c,
            Destination_Postal_Code__c,
            Recipient_Phone__c,
            Estimated_Delivery__c,
            Original_Estimated_Delivery__c,
            Delivery_Instructions__c,
            Reschedule_Count__c,
            Delivered_At__c,
            Proof_Id__c,
            Verification_Failures__c,
            Verification_Locked_Until__c
          FROM Shipment__c
          WHERE Name = :key
          WITH SYSTEM_MODE
          LIMIT 1
          FOR UPDATE
        ]
      : [
          SELECT
            Id,
            Name,
            Status__c,
            Recipient_Name__c,
            Recipient_Address__c,
            Destination_City__c,
            Destination_Postal_Code__c,
            Recipient_Phone__c,
            Estimated_Delivery__c,
            Original_Estimated_Delivery__c,
            Delivery_Instructions__c,
            Reschedule_Count__c,
            Delivered_At__c,
            Proof_Id__c,
            Verification_Failures__c,
            Verification_Locked_Until__c
          FROM Shipment__c
          WHERE Name = :key
          WITH SYSTEM_MODE
          LIMIT 1
        ];
    return rows.isEmpty() ? null : rows[0];
  }

  /** Returns null when the caller proved to be the recipient, otherwise the message to show. */
  private static String verify(
    Shipment__c shipment,
    String postalCode,
    Boolean resetOnSuccess
  ) {
    if (shipment == null) {
      return MSG_NOT_FOUND;
    }
    Datetime now = RutaCargoDates.now();
    if (
      shipment.Verification_Locked_Until__c != null &&
      shipment.Verification_Locked_Until__c > now
    ) {
      return MSG_LOCKED;
    }
    String entered = postalCode == null ? '' : postalCode.deleteWhitespace();
    String expected = shipment.Destination_Postal_Code__c == null
      ? null
      : shipment.Destination_Postal_Code__c.deleteWhitespace();
    if (expected == null || entered != expected) {
      registerFailure(shipment, now);
      return MSG_MISMATCH; // AC-002.3
    }
    if (resetOnSuccess) {
      resetFailures(shipment);
    }
    return null;
  }

  private static void registerFailure(Shipment__c shipment, Datetime now) {
    Integer failures =
      (shipment.Verification_Failures__c == null
        ? 0
        : shipment.Verification_Failures__c.intValue()) + 1;
    Shipment__c change = new Shipment__c(
      Id = shipment.Id,
      Verification_Failures__c = failures
    );
    if (failures >= ShipmentConstants.MAX_VERIFICATION_FAILURES) {
      change.Verification_Failures__c = 0;
      change.Verification_Locked_Until__c = now.addMinutes(
        ShipmentConstants.VERIFICATION_LOCK_MINUTES
      );
    }
    Database.update(change, AccessLevel.SYSTEM_MODE);
  }

  private static void resetFailures(Shipment__c shipment) {
    if (
      shipment.Verification_Failures__c != null &&
      shipment.Verification_Failures__c > 0
    ) {
      Database.update(
        new Shipment__c(Id = shipment.Id, Verification_Failures__c = 0),
        AccessLevel.SYSTEM_MODE
      );
      shipment.Verification_Failures__c = 0;
    }
  }

  private static Integer rescheduleCount(Shipment__c shipment) {
    return shipment.Reschedule_Count__c == null
      ? 0
      : shipment.Reschedule_Count__c.intValue();
  }

  private static Date rescheduleMinDate() {
    return RutaCargoDates.today().addDays(1);
  }

  private static Date rescheduleMaxDate(Shipment__c shipment) {
    Date original = shipment.Original_Estimated_Delivery__c != null
      ? shipment.Original_Estimated_Delivery__c
      : shipment.Estimated_Delivery__c;
    return original == null
      ? null
      : original.addDays(ShipmentConstants.RESCHEDULE_WINDOW_DAYS);
  }

  @TestVisible
  private static String rescheduleBlockedReason(Shipment__c shipment) {
    if (
      !ShipmentConstants.RESCHEDULABLE_STATUSES.contains(shipment.Status__c)
    ) {
      return 'Only shipments that are Picked up or In transit can be rescheduled.'; // AC-003.3
    }
    if (rescheduleCount(shipment) >= ShipmentConstants.MAX_RESCHEDULES) {
      return 'This delivery has already been rescheduled ' +
        ShipmentConstants.MAX_RESCHEDULES +
        ' times.'; // AC-003.4
    }
    Date maxDate = rescheduleMaxDate(shipment);
    if (maxDate == null || maxDate < rescheduleMinDate()) {
      return 'This delivery can no longer be rescheduled online.';
    }
    return null;
  }

  private static Result failure(String message) {
    Result result = new Result();
    result.success = false;
    result.message = message;
    return result;
  }

  // AC-002.2 — only the recipient's own delivery data; never price, cost or notes (BR-03).
  private static Result success(Shipment__c shipment) {
    DeliveryDetails details = new DeliveryDetails();
    details.trackingNumber = shipment.Name;
    details.status = shipment.Status__c;
    details.recipientName = shipment.Recipient_Name__c;
    details.deliveryAddress = shipment.Recipient_Address__c;
    details.destinationCity = shipment.Destination_City__c;
    details.destinationPostalCode = shipment.Destination_Postal_Code__c;
    details.contactPhone = shipment.Recipient_Phone__c;
    details.estimatedDelivery = shipment.Estimated_Delivery__c;
    details.deliveryInstructions = shipment.Delivery_Instructions__c;
    details.deliveredAt = shipment.Delivered_At__c;
    details.canDownloadProof =
      shipment.Status__c == ShipmentConstants.STATUS_DELIVERED &&
      String.isNotBlank(shipment.Proof_Id__c);
    details.rescheduleBlockedReason = rescheduleBlockedReason(shipment);
    details.canReschedule = details.rescheduleBlockedReason == null;
    details.reschedulesLeft = Math.max(
      0,
      ShipmentConstants.MAX_RESCHEDULES - rescheduleCount(shipment)
    );
    if (details.canReschedule) {
      details.rescheduleMinDate = rescheduleMinDate();
      details.rescheduleMaxDate = rescheduleMaxDate(shipment);
    }
    Result result = new Result();
    result.success = true;
    result.details = details;
    return result;
  }
}
