/**
 * REQ-004 — applies one EntregaYa status change to a shipment.
 * WITHOUT SHARING: the integration user must reach every shipment; who may call it is
 * restricted by the EntregaYa_Integration permission set (BR-04).
 */
public without sharing class ShipmentStatusUpdateService {
  public static final String RESULT_UPDATED = 'UPDATED';
  public static final String RESULT_IGNORED = 'IGNORED';

  public static final String ERR_INVALID_REQUEST = 'INVALID_REQUEST';
  public static final String ERR_NOT_FOUND = 'TRACKING_NUMBER_NOT_FOUND';
  public static final String ERR_INVALID_STATUS = 'INVALID_STATUS';
  public static final String ERR_INVALID_TIMESTAMP = 'INVALID_TIMESTAMP';

  private static final Pattern ISO_8601 = Pattern.compile(
    '^(\\d{4})-(\\d{2})-(\\d{2})T(\\d{2}):(\\d{2}):(\\d{2})(\\.\\d{1,9})?(Z|[+-]\\d{2}:?\\d{2})$'
  );

  public class StatusUpdate {
    public String trackingNumber;
    public String status;
    public String location;
    public String timestamp;
    public String proofId;
  }

  public class UpdateException extends Exception {
    public Integer httpStatus;
    public String code;
    public UpdateException(Integer httpStatus, String code, String message) {
      this(message);
      this.httpStatus = httpStatus;
      this.code = code;
    }
  }

  public class Outcome {
    public String result;
    public String trackingNumber;
    public String status;
    public String message;
  }

  public static Outcome apply(StatusUpdate change) {
    if (change == null || String.isBlank(change.trackingNumber)) {
      throw new UpdateException(
        400,
        ERR_INVALID_REQUEST,
        'trackingNumber is required.'
      );
    }
    String trackingNumber = change.trackingNumber.trim().toUpperCase();
    // AC-004.3: invalid status
    String status = ShipmentConstants.canonicalStatus(change.status);
    if (status == null) {
      throw new UpdateException(
        400,
        ERR_INVALID_STATUS,
        'Invalid status "' +
          change.status +
          '". Allowed values: ' +
          String.join(ShipmentConstants.STATUSES, ', ') +
          '.'
      );
    }
    Datetime occurredAt = parseTimestamp(change.timestamp);

    List<Shipment__c> rows = [
      SELECT Id, Name, Status__c, Last_Update__c
      FROM Shipment__c
      WHERE Name = :trackingNumber
      WITH SYSTEM_MODE
      LIMIT 1
      FOR UPDATE
    ];
    // AC-004.3: nonexistent tracking number
    if (rows.isEmpty()) {
      throw new UpdateException(
        404,
        ERR_NOT_FOUND,
        'No shipment with tracking number ' + trackingNumber + '.'
      );
    }
    Shipment__c shipment = rows[0];

    Outcome outcome = new Outcome();
    outcome.trackingNumber = shipment.Name;
    // AC-004.4: an update older than the last one recorded is ignored.
    if (
      shipment.Last_Update__c != null &&
      occurredAt < shipment.Last_Update__c
    ) {
      outcome.result = RESULT_IGNORED;
      outcome.status = shipment.Status__c;
      outcome.message = 'Ignored: a more recent update was already recorded.';
      return outcome;
    }

    // AC-004.2
    shipment.Status__c = status;
    shipment.Last_Location__c = String.isBlank(change.location)
      ? null
      : change.location.trim().left(255);
    shipment.Last_Update__c = occurredAt;
    if (status == ShipmentConstants.STATUS_DELIVERED) {
      shipment.Delivered_At__c = occurredAt;
      if (String.isNotBlank(change.proofId)) {
        shipment.Proof_Id__c = change.proofId.trim().left(40);
      }
    }
    Database.update(shipment, AccessLevel.SYSTEM_MODE);

    outcome.result = RESULT_UPDATED;
    outcome.status = status;
    outcome.message = 'Shipment updated.';
    return outcome;
  }

  /** ISO 8601 with offset, e.g. 2026-11-20T10:00:00-06:00 or 2026-11-20T16:00:00Z. */
  public static Datetime parseTimestamp(String value) {
    Matcher m = value == null ? null : ISO_8601.matcher(value.trim());
    if (m == null || !m.matches()) {
      throw new UpdateException(
        400,
        ERR_INVALID_TIMESTAMP,
        'timestamp must be ISO 8601 with a time zone, e.g. 2026-11-20T10:00:00-06:00.'
      );
    }
    Datetime local = Datetime.newInstanceGmt(
      Integer.valueOf(m.group(1)),
      Integer.valueOf(m.group(2)),
      Integer.valueOf(m.group(3)),
      Integer.valueOf(m.group(4)),
      Integer.valueOf(m.group(5)),
      Integer.valueOf(m.group(6))
    );
    String zone = m.group(8);
    if (zone == 'Z') {
      return local;
    }
    String digits = zone.substring(1).remove(':');
    Integer offsetMinutes =
      Integer.valueOf(digits.substring(0, 2)) * 60 +
      Integer.valueOf(digits.substring(2, 4));
    if (zone.startsWith('-')) {
      offsetMinutes = -offsetMinutes;
    }
    // local = UTC + offset  =>  UTC = local - offset
    return local.addMinutes(-offsetMinutes);
  }
}
