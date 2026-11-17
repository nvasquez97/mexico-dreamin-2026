/** REQ-004 — carrier status updates (Apex REST POST /entregaya/v1/status-updates). */
@IsTest
private class EntregaYaStatusResourceTest {
  @TestSetup
  static void setup() {
    Account acme = RutaCargoTestFactory.customer('Acme');
    Shipment__c s = RutaCargoTestFactory.shipment(acme.Id, 'In transit');
    s.Last_Update__c = Datetime.newInstanceGmt(2026, 11, 20, 12, 0, 0);
    insert s;
  }

  private static String trackingNumber() {
    return [SELECT Name FROM Shipment__c LIMIT 1].Name;
  }

  private static Map<String, Object> post(String body) {
    RestRequest request = new RestRequest();
    request.requestURI = '/services/apexrest/entregaya/v1/status-updates';
    request.httpMethod = 'POST';
    request.requestBody = body == null ? null : Blob.valueOf(body);
    RestContext.request = request;
    RestContext.response = new RestResponse();
    EntregaYaStatusResource.receive();
    Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(
      RestContext.response.responseBody.toString()
    );
    result.put('httpStatus', RestContext.response.statusCode);
    return result;
  }

  private static String body(
    String tracking,
    String status,
    String location,
    String timestamp,
    String proofId
  ) {
    return JSON.serialize(
      new Map<String, Object>{
        'trackingNumber' => tracking,
        'status' => status,
        'location' => location,
        'timestamp' => timestamp,
        'proofId' => proofId
      }
    );
  }

  private static Shipment__c reload() {
    return [
      SELECT
        Status__c,
        Last_Location__c,
        Last_Update__c,
        Delivered_At__c,
        Proof_Id__c
      FROM Shipment__c
      LIMIT 1
    ];
  }

  @IsTest
  static void ac004_1_and_2_updatesStatusLocationAndDate() {
    Map<String, Object> result = post(
      body(
        trackingNumber(),
        'Out for delivery',
        'Monterrey, NL',
        '2026-11-20T10:00:00-06:00',
        null
      )
    );
    Assert.areEqual(200, result.get('httpStatus'));
    Assert.areEqual('UPDATED', result.get('result'));
    Shipment__c s = reload();
    Assert.areEqual('Out for delivery', s.Status__c);
    Assert.areEqual('Monterrey, NL', s.Last_Location__c);
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0),
      s.Last_Update__c,
      '10:00 -06:00 = 16:00 UTC'
    );
    Assert.isNull(s.Delivered_At__c);
  }

  @IsTest
  static void ac004_2_deliveredSavesTheMomentAndTheProofId() {
    Map<String, Object> result = post(
      body(
        trackingNumber().toLowerCase(),
        'delivered',
        'Monterrey, NL',
        '2026-11-21T09:30:00Z',
        'PRF-88231'
      )
    );
    Assert.areEqual(200, result.get('httpStatus'));
    Shipment__c s = reload();
    Assert.areEqual(
      'Delivered',
      s.Status__c,
      'Status is matched case-insensitively and stored canonically'
    );
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 11, 21, 9, 30, 0),
      s.Delivered_At__c
    );
    Assert.areEqual('PRF-88231', s.Proof_Id__c);
  }

  @IsTest
  static void ac004_3_unknownTrackingNumberIsRejected() {
    Map<String, Object> result = post(
      body('RC999999999', 'In transit', 'X', '2026-11-21T09:30:00Z', null)
    );
    Assert.areEqual(404, result.get('httpStatus'));
    Assert.areEqual('TRACKING_NUMBER_NOT_FOUND', result.get('errorCode'));
    Assert.isTrue(((String) result.get('message')).contains('RC999999999'));
  }

  @IsTest
  static void ac004_3_invalidStatusIsRejected() {
    Map<String, Object> result = post(
      body(trackingNumber(), 'Lost in space', 'X', '2026-11-21T09:30:00Z', null)
    );
    Assert.areEqual(400, result.get('httpStatus'));
    Assert.areEqual('INVALID_STATUS', result.get('errorCode'));
    Assert.isTrue(((String) result.get('message')).contains('Allowed values'));
    Assert.areEqual('In transit', reload().Status__c);
  }

  @IsTest
  static void ac004_3_malformedRequestsAreRejected() {
    Assert.areEqual('INVALID_REQUEST', post(null).get('errorCode'));
    Assert.areEqual('INVALID_REQUEST', post('{not json').get('errorCode'));
    Assert.areEqual(
      'INVALID_REQUEST',
      post(body(null, 'In transit', 'X', '2026-11-21T09:30:00Z', null))
        .get('errorCode')
    );
    Map<String, Object> badTime = post(
      body(trackingNumber(), 'In transit', 'X', '21/11/2026 09:30', null)
    );
    Assert.areEqual(400, badTime.get('httpStatus'));
    Assert.areEqual('INVALID_TIMESTAMP', badTime.get('errorCode'));
  }

  @IsTest
  static void ac004_4_olderUpdatesAreIgnored() {
    // Last update recorded: 2026-11-20 12:00 UTC. 05:00 -06:00 = 11:00 UTC is older.
    Map<String, Object> result = post(
      body(
        trackingNumber(),
        'Picked up',
        'CDMX',
        '2026-11-20T05:00:00-06:00',
        null
      )
    );
    Assert.areEqual(200, result.get('httpStatus'));
    Assert.areEqual('IGNORED', result.get('result'));
    Shipment__c s = reload();
    Assert.areEqual('In transit', s.Status__c);
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 11, 20, 12, 0, 0),
      s.Last_Update__c
    );
  }

  @IsTest
  static void parsesTimestampOffsets() {
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 11, 20, 4, 30, 0),
      ShipmentStatusUpdateService.parseTimestamp('2026-11-20T10:00:00+05:30')
    );
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 11, 20, 16, 0, 0),
      ShipmentStatusUpdateService.parseTimestamp('2026-11-20T10:00:00.123-0600')
    );
  }

  @IsTest
  static void br04_onlyTheEntregaYaPermissionSetGrantsTheEndpoint() {
    ApexClass endpoint = [
      SELECT Id
      FROM ApexClass
      WHERE Name = 'EntregaYaStatusResource'
      LIMIT 1
    ];
    List<String> grantedBy = new List<String>();
    for (SetupEntityAccess access : [
      SELECT Parent.Name
      FROM SetupEntityAccess
      WHERE SetupEntityId = :endpoint.Id AND Parent.IsOwnedByProfile = FALSE
    ]) {
      grantedBy.add(access.Parent.Name);
    }
    Assert.areEqual(new List<String>{ 'EntregaYa_Integration' }, grantedBy);
  }
}
