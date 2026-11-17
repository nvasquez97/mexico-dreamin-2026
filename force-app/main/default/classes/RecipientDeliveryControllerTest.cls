/** REQ-002 (delivery details, proof of delivery) and REQ-003 (reschedule). */
@IsTest
private class RecipientDeliveryControllerTest {
  private static final String POSTAL = '64000';

  private class ProofMock implements HttpCalloutMock {
    Integer status;
    String body;
    Boolean fail;
    String endpoint;
    ProofMock(Integer status, String body) {
      this.status = status;
      this.body = body;
      this.fail = false;
    }
    public HttpResponse respond(HttpRequest request) {
      endpoint = request.getEndpoint();
      Assert.areEqual('GET', request.getMethod());
      if (fail) {
        throw new CalloutException('Read timed out');
      }
      HttpResponse response = new HttpResponse();
      response.setStatusCode(status);
      response.setBody(body);
      return response;
    }
  }

  private static Shipment__c create(String status) {
    RutaCargoTestFactory.pinToday();
    Account acme = RutaCargoTestFactory.customer('Acme');
    Shipment__c s = RutaCargoTestFactory.shipment(acme.Id, status);
    if (status == 'Delivered') {
      s.Proof_Id__c = 'PRF-88231';
      s.Delivered_At__c = RutaCargoTestFactory.NOW.addDays(-1);
    }
    insert s;
    return [
      SELECT
        Id,
        Name,
        Estimated_Delivery__c,
        Reschedule_Count__c,
        Verification_Failures__c,
        Verification_Locked_Until__c
      FROM Shipment__c
      WHERE Id = :s.Id
    ];
  }

  private static Shipment__c reload(Id id) {
    return [
      SELECT
        Estimated_Delivery__c,
        Original_Estimated_Delivery__c,
        Delivery_Instructions__c,
        Reschedule_Count__c,
        Verification_Failures__c,
        Verification_Locked_Until__c
      FROM Shipment__c
      WHERE Id = :id
    ];
  }

  // ---------------------------------------------------------------- REQ-002

  @IsTest
  static void ac002_1_and_2_postalCodeOpensTheDeliveryDetails() {
    Shipment__c s = create('In transit');
    RecipientDeliveryService.Result r = RecipientDeliveryController.getDeliveryDetails(
      s.Name.toLowerCase(),
      ' 64000 '
    );
    Assert.isTrue(r.success, '' + r.message);
    Assert.areEqual('Lucía Hernández', r.details.recipientName);
    Assert.areEqual('Av. Juárez 120, Col. Centro', r.details.deliveryAddress);
    Assert.areEqual('81 5123 4567', r.details.contactPhone);
    Assert.areEqual(s.Estimated_Delivery__c, r.details.estimatedDelivery);
    Assert.areEqual('Tocar el timbre', r.details.deliveryInstructions);
    // BR-03: no internal data or price
    String json = JSON.serialize(r).toLowerCase();
    Assert.isFalse(
      json.contains('price') ||
        json.contains('cost') ||
        json.contains('internal only') ||
        json.contains('proofid')
    );
  }

  @IsTest
  static void ac002_3_wrongPostalCodeDoesNotMatch() {
    Shipment__c s = create('In transit');
    RecipientDeliveryService.Result r = RecipientDeliveryController.getDeliveryDetails(
      s.Name,
      '11111'
    );
    Assert.isFalse(r.success);
    Assert.areEqual('The details do not match this shipment', r.message);
    Assert.isNull(r.details);
    Assert.areEqual(1, reload(s.Id).Verification_Failures__c);
  }

  @IsTest
  static void ac002_3_repeatedWrongPostalCodesLockTheShipment() {
    Shipment__c s = create('In transit');
    for (Integer i = 0; i < ShipmentConstants.MAX_VERIFICATION_FAILURES; i++) {
      RecipientDeliveryController.getDeliveryDetails(s.Name, '0000' + i);
    }
    Assert.isNotNull(reload(s.Id).Verification_Locked_Until__c);
    RecipientDeliveryService.Result locked = RecipientDeliveryController.getDeliveryDetails(
      s.Name,
      POSTAL
    );
    Assert.isFalse(
      locked.success,
      'Even the right code is refused while locked'
    );
    Assert.areEqual(RecipientDeliveryService.MSG_LOCKED, locked.message);

    RutaCargoDates.nowOverride = RutaCargoTestFactory.NOW.addMinutes(
      ShipmentConstants.VERIFICATION_LOCK_MINUTES + 1
    );
    Assert.isTrue(
      RecipientDeliveryController.getDeliveryDetails(s.Name, POSTAL).success
    );
  }

  @IsTest
  static void unknownTrackingNumber() {
    RutaCargoTestFactory.pinToday();
    Assert.areEqual(
      RecipientDeliveryService.MSG_NOT_FOUND,
      RecipientDeliveryController.getDeliveryDetails('RC999999999', POSTAL)
        .message
    );
    Assert.areEqual(
      RecipientDeliveryService.MSG_NOT_FOUND,
      RecipientDeliveryController.getDeliveryDetails('<script>', POSTAL).message
    );
  }

  @IsTest
  static void ac002_4_downloadsTheProofFromEntregaYaWithoutStoringIt() {
    Shipment__c s = create('Delivered');
    ProofMock mock = new ProofMock(
      200,
      '{"proofId":"PRF-88231","trackingNumber":"' +
        s.Name +
        '","signedBy":"Ana López","fileName":"proof-of-delivery.pdf","pdfBase64":"JVBERi0xLjQK"}'
    );
    Test.setMock(HttpCalloutMock.class, mock);
    Integer filesBefore =
      [SELECT COUNT() FROM ContentVersion] + [SELECT COUNT() FROM Attachment];

    Test.startTest();
    RecipientDeliveryService.ProofResult r = RecipientDeliveryController.downloadProofOfDelivery(
      s.Name,
      POSTAL
    );
    Test.stopTest();

    Assert.isTrue(r.success, '' + r.message);
    Assert.areEqual('JVBERi0xLjQK', r.pdfBase64);
    Assert.areEqual('proof-of-delivery.pdf', r.fileName);
    Assert.areEqual('Ana López', r.signedBy);
    Assert.areEqual('callout:EntregaYa/proofs/PRF-88231', mock.endpoint);
    Assert.areEqual(
      filesBefore,
      [SELECT COUNT() FROM ContentVersion] + [SELECT COUNT() FROM Attachment],
      'The PDF is not stored'
    );
    Assert.isTrue(
      RecipientDeliveryController.getDeliveryDetails(s.Name, POSTAL)
        .details.canDownloadProof
    );
  }

  @IsTest
  static void ac002_4_proofRequiresTheRecipientAndADeliveredShipment() {
    Shipment__c delivered = create('Delivered');
    Test.setMock(HttpCalloutMock.class, new ProofMock(200, '{}'));
    Assert.areEqual(
      'The details do not match this shipment',
      RecipientDeliveryController.downloadProofOfDelivery(
          delivered.Name,
          '99999'
        )
        .message
    );
    Shipment__c inTransit = RutaCargoTestFactory.insertShipment(
      [SELECT Account__c FROM Shipment__c WHERE Id = :delivered.Id].Account__c,
      'In transit'
    );
    RecipientDeliveryService.ProofResult r = RecipientDeliveryController.downloadProofOfDelivery(
      inTransit.Name,
      POSTAL
    );
    Assert.isFalse(r.success);
    Assert.areEqual(RecipientDeliveryService.MSG_PROOF_NOT_READY, r.message);
  }

  @IsTest
  static void ac002_5_entregaYaErrorsShowTheRetryMessage() {
    Shipment__c s = create('Delivered');
    for (Integer status : new List<Integer>{ 401, 404, 503 }) {
      Test.setMock(
        HttpCalloutMock.class,
        new ProofMock(status, '{"error":"x"}')
      );
      RecipientDeliveryService.ProofResult r = RecipientDeliveryController.downloadProofOfDelivery(
        s.Name,
        POSTAL
      );
      Assert.isFalse(r.success);
      Assert.areEqual(
        'We could not get the proof of delivery, please try again later',
        r.message
      );
    }
    Test.setMock(HttpCalloutMock.class, new ProofMock(200, 'not json'));
    Assert.isFalse(
      RecipientDeliveryController.downloadProofOfDelivery(s.Name, POSTAL)
        .success
    );
    Test.setMock(
      HttpCalloutMock.class,
      new ProofMock(
        200,
        '{"proofId":"PRF-88231","trackingNumber":"RC000000001","pdfBase64":"JVBE"}'
      )
    );
    Assert.isFalse(
      RecipientDeliveryController.downloadProofOfDelivery(s.Name, POSTAL)
        .success,
      'Proof of another shipment'
    );
  }

  @IsTest
  static void ac002_5_entregaYaTimeoutShowsTheRetryMessage() {
    Shipment__c s = create('Delivered');
    ProofMock mock = new ProofMock(200, '');
    mock.fail = true;
    Test.setMock(HttpCalloutMock.class, mock);
    RecipientDeliveryService.ProofResult r = RecipientDeliveryController.downloadProofOfDelivery(
      s.Name,
      POSTAL
    );
    Assert.isFalse(r.success);
    Assert.areEqual(
      'We could not get the proof of delivery, please try again later',
      r.message
    );
  }

  // ---------------------------------------------------------------- REQ-003

  @IsTest
  static void ac003_1_recipientChangesDateAndInstructions() {
    Shipment__c s = create('In transit'); // estimated 2026-11-20
    Date newDate = RutaCargoTestFactory.TODAY.addDays(5);
    RecipientDeliveryService.Result r = RecipientDeliveryController.rescheduleDelivery(
      s.Name,
      POSTAL,
      newDate,
      '  Dejar con el vigilante  '
    );
    Assert.isTrue(r.success, '' + r.message);
    Shipment__c saved = reload(s.Id);
    Assert.areEqual(newDate, saved.Estimated_Delivery__c);
    Assert.areEqual('Dejar con el vigilante', saved.Delivery_Instructions__c);
    Assert.areEqual(
      s.Estimated_Delivery__c,
      saved.Original_Estimated_Delivery__c
    );
    Assert.areEqual(1, saved.Reschedule_Count__c);
  }

  @IsTest
  static void ac003_2_newDateBetweenTomorrowAndSevenDaysAfterTheOriginalEstimate() {
    Shipment__c s = create('In transit');
    Date original = s.Estimated_Delivery__c; // 2026-11-20
    Date tomorrow = RutaCargoTestFactory.TODAY.addDays(1);
    for (
      Date invalid : new List<Date>{
        null,
        RutaCargoTestFactory.TODAY,
        original.addDays(8)
      }
    ) {
      RecipientDeliveryService.Result r = RecipientDeliveryController.rescheduleDelivery(
        s.Name,
        POSTAL,
        invalid,
        null
      );
      Assert.isFalse(r.success, 'Date should be rejected: ' + invalid);
      Assert.isTrue(
        r.message.startsWith('Choose a date between'),
        '' + r.message
      );
    }
    Assert.isTrue(
      RecipientDeliveryController.rescheduleDelivery(
          s.Name,
          POSTAL,
          tomorrow,
          null
        )
        .success
    );
    // The window stays anchored to the ORIGINAL estimate after a first reschedule.
    Assert.isTrue(
      RecipientDeliveryController.rescheduleDelivery(
          s.Name,
          POSTAL,
          original.addDays(7),
          null
        )
        .success
    );
    Assert.areEqual(original, reload(s.Id).Original_Estimated_Delivery__c);
  }

  @IsTest
  static void ac003_2_detailsExposeTheAllowedWindow() {
    Shipment__c s = create('Picked up');
    RecipientDeliveryService.DeliveryDetails d = RecipientDeliveryController.getDeliveryDetails(
        s.Name,
        POSTAL
      )
      .details;
    Assert.isTrue(d.canReschedule);
    Assert.areEqual(RutaCargoTestFactory.TODAY.addDays(1), d.rescheduleMinDate);
    Assert.areEqual(s.Estimated_Delivery__c.addDays(7), d.rescheduleMaxDate);
    Assert.areEqual(2, d.reschedulesLeft);
  }

  @IsTest
  static void ac003_3_onlyPickedUpOrInTransitCanBeRescheduled() {
    Shipment__c s = create('Picked up');
    Assert.isTrue(
      RecipientDeliveryController.rescheduleDelivery(
          s.Name,
          POSTAL,
          RutaCargoTestFactory.TODAY.addDays(3),
          null
        )
        .success
    );
    Id accountId = [SELECT Account__c FROM Shipment__c WHERE Id = :s.Id]
    .Account__c;
    for (
      String status : new List<String>{
        'Requested',
        'Out for delivery',
        'Delivered',
        'Exception'
      }
    ) {
      Shipment__c other = RutaCargoTestFactory.insertShipment(
        accountId,
        status
      );
      RecipientDeliveryService.Result r = RecipientDeliveryController.rescheduleDelivery(
        other.Name,
        POSTAL,
        RutaCargoTestFactory.TODAY.addDays(3),
        null
      );
      Assert.isFalse(r.success, status);
      Assert.isTrue(
        r.message.contains('Picked up or In transit'),
        '' + r.message
      );
      Assert.isFalse(
        RecipientDeliveryController.getDeliveryDetails(other.Name, POSTAL)
          .details.canReschedule
      );
    }
  }

  @IsTest
  static void ac003_4_atMostTwoReschedules() {
    Shipment__c s = create('In transit');
    Assert.isTrue(
      RecipientDeliveryController.rescheduleDelivery(
          s.Name,
          POSTAL,
          RutaCargoTestFactory.TODAY.addDays(2),
          null
        )
        .success
    );
    Assert.isTrue(
      RecipientDeliveryController.rescheduleDelivery(
          s.Name,
          POSTAL,
          RutaCargoTestFactory.TODAY.addDays(3),
          null
        )
        .success
    );
    RecipientDeliveryService.Result third = RecipientDeliveryController.rescheduleDelivery(
      s.Name,
      POSTAL,
      RutaCargoTestFactory.TODAY.addDays(4),
      null
    );
    Assert.isFalse(third.success);
    Assert.isTrue(third.message.contains('2 times'), third.message);
    Assert.areEqual(2, reload(s.Id).Reschedule_Count__c);
  }

  @IsTest
  static void ac003_5_savedDateIsShownAndTrackedForAgents() {
    Shipment__c s = create('In transit');
    Date newDate = RutaCargoTestFactory.TODAY.addDays(4); // Sunday 2026-11-22
    RecipientDeliveryService.Result r = RecipientDeliveryController.rescheduleDelivery(
      s.Name,
      POSTAL,
      newDate,
      null
    );
    Assert.isTrue(r.success);
    Assert.areEqual(newDate, r.details.estimatedDelivery);
    Assert.isTrue(r.message.contains('Nov 22, 2026'), '' + r.message);
    // Agents see when each change happened through field history on these fields.
    Map<String, Schema.SObjectField> fields = Schema.SObjectType.Shipment__c.fields.getMap();
    for (
      String f : new List<String>{
        'Estimated_Delivery__c',
        'Delivery_Instructions__c',
        'Reschedule_Count__c'
      }
    ) {
      Assert.isNotNull(fields.get(f));
    }
    Assert.areEqual(
      3,
      [
        SELECT COUNT()
        FROM FieldDefinition
        WHERE
          EntityDefinition.QualifiedApiName = 'Shipment__c'
          AND QualifiedApiName IN (
            'Estimated_Delivery__c',
            'Delivery_Instructions__c',
            'Reschedule_Count__c'
          )
          AND IsFieldHistoryTracked = TRUE
      ],
      'Reschedule fields must have history tracking'
    );
  }

  @IsTest
  static void rescheduleRequiresTheRecipientAndValidInstructions() {
    Shipment__c s = create('In transit');
    Assert.areEqual(
      'The details do not match this shipment',
      RecipientDeliveryController.rescheduleDelivery(
          s.Name,
          '00000',
          RutaCargoTestFactory.TODAY.addDays(2),
          null
        )
        .message
    );
    RecipientDeliveryService.Result r = RecipientDeliveryController.rescheduleDelivery(
      s.Name,
      POSTAL,
      RutaCargoTestFactory.TODAY.addDays(2),
      'x'.repeat(1001)
    );
    Assert.isFalse(r.success);
    Assert.areEqual(0, reload(s.Id).Reschedule_Count__c);
  }
}
