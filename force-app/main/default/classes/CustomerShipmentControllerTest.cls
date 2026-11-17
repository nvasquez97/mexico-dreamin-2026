/** REQ-006 (request a shipment) and REQ-007 (my shipments), run as a site user. */
@IsTest
private class CustomerShipmentControllerTest {
  private static ShipmentRequestService.ShipmentRequest request() {
    ShipmentRequestService.ShipmentRequest r = new ShipmentRequestService.ShipmentRequest();
    r.pickupAddress = 'Calle Fresno 214, Col. Santa María la Ribera';
    r.pickupCity = 'Ciudad de México';
    r.pickupPostalCode = '06400';
    r.pickupDate = Date.newInstance(2026, 11, 19); // Thursday (tomorrow)
    r.recipientName = 'Mateo García';
    r.recipientAddress = 'Av. Juárez 120, Col. Centro';
    r.destinationCity = 'Puebla';
    r.destinationPostalCode = '72000';
    r.recipientPhone = '222 512 3456';
    r.recipientEmail = 'mateo@correo.example';
    r.serviceType = 'Standard';
    r.weightKg = 2.5;
    r.packageDescription = 'Café de grano';
    r.declaredValue = 1000;
    return r;
  }

  private static String errorOf(ShipmentRequestService.ShipmentRequest r) {
    try {
      CustomerShipmentController.getQuote(r);
      return null;
    } catch (AuraHandledException e) {
      return e.getMessage();
    }
  }

  // ---------------------------------------------------------------- REQ-006

  @IsTest
  static void ac006_1_requiredAndOptionalFields() {
    User u = RutaCargoTestFactory.customerUser('Acme', 'ana@acme.example');
    RutaCargoTestFactory.pinToday();
    System.runAs(u) {
      String message = errorOf(new ShipmentRequestService.ShipmentRequest());
      for (
        String expected : new List<String>{
          'Pickup address',
          'Pickup city',
          'Pickup postal code',
          'Pickup date',
          'Recipient name',
          'Recipient address',
          'Destination city',
          'Destination postal code',
          'Recipient phone',
          'Recipient email',
          'Service type',
          'Weight',
          'Declared value',
          'Description of the contents'
        }
      ) {
        Assert.isTrue(
          message.contains(expected),
          'Missing: ' + expected + ' in ' + message
        );
      }
      ShipmentRequestService.ShipmentRequest optional = request();
      optional.customerReference = null;
      optional.deliveryInstructions = null;
      Assert.isNull(
        errorOf(optional),
        'Order reference and instructions are optional'
      );
    }
  }

  @IsTest
  static void ac006_2_priceWithTheCurrentRateBeforeConfirming() {
    User u = RutaCargoTestFactory.customerUser('Acme', 'ana@acme.example');
    RutaCargoTestFactory.pinToday();
    System.runAs(u) {
      ShipmentRequestService.QuoteResult q = CustomerShipmentController.getQuote(
        request()
      );
      Assert.areEqual(180, q.price.total); // 120 + 18 * 2.5 + 1.5% of 1,000
      ShipmentRequestService.ShipmentRequest express = request();
      express.serviceType = 'Express';
      Assert.areEqual(
        220 + 75 + 15,
        CustomerShipmentController.getQuote(express).price.total
      );
    }
  }

  @IsTest
  static void ac006_3_pickupIsABusinessDayBetweenTomorrowAndFifteenDays() {
    User u = RutaCargoTestFactory.customerUser('Acme', 'ana@acme.example');
    RutaCargoTestFactory.pinToday(); // Wednesday 2026-11-18
    System.runAs(u) {
      ShipmentRequestService.PickupWindow w = CustomerShipmentController.getPickupWindow();
      Assert.areEqual(Date.newInstance(2026, 11, 19), w.minDate);
      Assert.areEqual(Date.newInstance(2026, 12, 3), w.maxDate);

      Map<Date, String> invalid = new Map<Date, String>{
        Date.newInstance(2026, 11, 18) => 'between', // today
        Date.newInstance(2026, 12, 4) => 'between', // 16 days
        Date.newInstance(2026, 11, 21) => 'business day' // Saturday
      };
      for (Date d : invalid.keySet()) {
        ShipmentRequestService.ShipmentRequest r = request();
        r.pickupDate = d;
        String message = errorOf(r);
        Assert.isTrue(
          message != null && message.contains(invalid.get(d)),
          d + ': ' + message
        );
      }
      ShipmentRequestService.ShipmentRequest lastDay = request();
      lastDay.pickupDate = Date.newInstance(2026, 12, 3); // Thursday, day 15
      Assert.isNull(errorOf(lastDay));
    }
  }

  @IsTest
  static void ac006_4_maximumWeightAndDeclaredValue() {
    User u = RutaCargoTestFactory.customerUser('Acme', 'ana@acme.example');
    RutaCargoTestFactory.pinToday();
    System.runAs(u) {
      ShipmentRequestService.ShipmentRequest limits = request();
      limits.weightKg = 30;
      limits.declaredValue = 50000;
      Assert.isNull(errorOf(limits));
      ShipmentRequestService.ShipmentRequest heavy = request();
      heavy.weightKg = 30.01;
      Assert.isTrue(errorOf(heavy).contains('at most 30'));
      ShipmentRequestService.ShipmentRequest valuable = request();
      valuable.declaredValue = 50000.01;
      Assert.isTrue(errorOf(valuable).contains('50,000'));
    }
  }

  @IsTest
  static void ac006_5_createsTheShipmentUnderTheCustomerInRequestedStatus() {
    User u = RutaCargoTestFactory.customerUser('Acme', 'ana@acme.example');
    RutaCargoTestFactory.pinToday();
    ShipmentRequestService.ShipmentRequest r = request();
    r.customerReference = ' PO-77 ';
    ShipmentRequestService.CreatedShipment created;
    System.runAs(u) {
      created = CustomerShipmentController.createShipment(r);
    }
    Assert.isTrue(
      Pattern.matches('RC[0-9]{9}', created.trackingNumber),
      created.trackingNumber
    ); // BR-05
    Assert.areEqual('Requested', created.status);
    Assert.areEqual(180, created.price);
    Shipment__c s = [
      SELECT
        Account__c,
        Status__c,
        Price__c,
        Customer_Reference__c,
        Recipient_Name__c
      FROM Shipment__c
      WHERE Name = :created.trackingNumber
    ];
    Assert.areEqual(u.AccountId, s.Account__c);
    Assert.areEqual('Requested', s.Status__c);
    Assert.areEqual('PO-77', s.Customer_Reference__c);
  }

  @IsTest
  static void br05_trackingNumbersAreConsecutive() {
    User u = RutaCargoTestFactory.customerUser('Acme', 'ana@acme.example');
    RutaCargoTestFactory.pinToday();
    System.runAs(u) {
      String first = CustomerShipmentController.createShipment(request())
        .trackingNumber;
      String second = CustomerShipmentController.createShipment(request())
        .trackingNumber;
      Assert.areEqual(
        Long.valueOf(first.substring(2)) + 1,
        Long.valueOf(second.substring(2))
      );
    }
  }

  @IsTest
  static void ac006_6_estimatedDeliveryAddsBusinessDays() {
    User u = RutaCargoTestFactory.customerUser('Acme', 'ana@acme.example');
    RutaCargoTestFactory.pinToday();
    System.runAs(u) {
      // Pickup Thursday 2026-11-19: Standard +5 business days = Thursday 26; Express +2 = Monday 23.
      Assert.areEqual(
        Date.newInstance(2026, 11, 26),
        CustomerShipmentController.getQuote(request()).estimatedDelivery
      );
      ShipmentRequestService.ShipmentRequest express = request();
      express.serviceType = 'Express';
      Assert.areEqual(
        Date.newInstance(2026, 11, 23),
        CustomerShipmentController.createShipment(express).estimatedDelivery
      );
    }
  }

  @IsTest
  static void requestRequiresALoggedInCustomer() {
    RutaCargoTestFactory.pinToday();
    try {
      CustomerShipmentController.createShipment(request()); // internal user: no account
      Assert.fail('Expected an error');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('log in'));
    }
  }

  // ---------------------------------------------------------------- REQ-007

  private static void seed(Id acmeId, Id globexId) {
    List<Shipment__c> rows = new List<Shipment__c>();
    for (Integer i = 0; i < 30; i++) {
      Shipment__c s = RutaCargoTestFactory.shipment(
        acmeId,
        Math.mod(i, 3) == 0 ? 'Delivered' : 'In transit'
      );
      s.Recipient_Name__c = i == 7 ? 'Valeria Torres' : 'Recipient ' + i;
      s.Customer_Reference__c = 'ACME-' + i;
      rows.add(s);
    }
    rows.add(RutaCargoTestFactory.shipment(globexId, 'In transit'));
    insert rows;
    for (Integer i = 0; i < 30; i++) {
      Test.setCreatedDate(
        rows[i].Id,
        RutaCargoTestFactory.NOW.addDays(-30 + i)
      );
    }
  }

  @IsTest
  static void ac007_1_listsOnlyTheCustomersShipmentsMostRecentFirst() {
    User u = RutaCargoTestFactory.customerUser('Acme', 'ana@acme.example');
    Account globex = RutaCargoTestFactory.customer('Globex');
    seed(u.AccountId, globex.Id);
    System.runAs(u) {
      CustomerShipmentController.ShipmentPage page = CustomerShipmentController.getMyShipments(
        null,
        null,
        0
      );
      Assert.areEqual(
        30,
        page.totalCount,
        'BR-07: never another customer\'s shipments'
      );
      Assert.areEqual(25, page.rows.size());
      Assert.isTrue(page.hasMore);
      for (Integer i = 1; i < page.rows.size(); i++) {
        Assert.isTrue(
          page.rows[i - 1].requestDate >= page.rows[i].requestDate,
          'Most recent first'
        );
      }
      CustomerShipmentController.ShipmentRow row = page.rows[0];
      Assert.areEqual('Recipient 29', row.recipientName);
      Assert.isNotNull(row.trackingNumber);
      Assert.isNotNull(row.destinationCity);
      Assert.isNotNull(row.status);
      Assert.isNotNull(row.serviceType);
      Assert.isNotNull(row.price);
      String json = JSON.serialize(page).toLowerCase();
      Assert.isFalse(
        json.contains('internal only') ||
          json.contains('carrier') ||
          json.contains('margin')
      );

      CustomerShipmentController.ShipmentPage second = CustomerShipmentController.getMyShipments(
        null,
        null,
        25
      );
      Assert.areEqual(5, second.rows.size());
      Assert.isFalse(second.hasMore);
    }
  }

  @IsTest
  static void ac007_2_filtersByStatusAndSearches() {
    User u = RutaCargoTestFactory.customerUser('Acme', 'ana@acme.example');
    Account globex = RutaCargoTestFactory.customer('Globex');
    seed(u.AccountId, globex.Id);
    String someTracking = [
      SELECT Name
      FROM Shipment__c
      WHERE Account__c = :u.AccountId AND Customer_Reference__c = 'ACME-12'
    ]
    .Name;
    System.runAs(u) {
      Assert.areEqual(
        10,
        CustomerShipmentController.getMyShipments('Delivered', null, 0)
          .totalCount
      );
      Assert.areEqual(
        20,
        CustomerShipmentController.getMyShipments('in transit', '', 0)
          .totalCount
      );
      Assert.areEqual(
        1,
        CustomerShipmentController.getMyShipments(null, 'valeria', 0)
          .totalCount,
        'by recipient'
      );
      Assert.areEqual(
        1,
        CustomerShipmentController.getMyShipments(null, someTracking, 0)
          .totalCount,
        'by tracking number'
      );
      Assert.areEqual(
        1,
        CustomerShipmentController.getMyShipments(null, 'acme-12', 0)
          .totalCount,
        'by reference'
      );
      Assert.areEqual(
        0,
        CustomerShipmentController.getMyShipments(null, '%', 0).totalCount,
        'wildcards are literal'
      );
      Assert.areEqual(
        1,
        CustomerShipmentController.getMyShipments('Delivered', 'ACME-12', 0)
          .totalCount
      );
      Assert.areEqual(6, CustomerShipmentController.getStatuses().size());
    }
  }

  @IsTest
  static void ac007_3_detailOfOwnShipmentOnly() {
    User u = RutaCargoTestFactory.customerUser('Acme', 'ana@acme.example');
    Account globex = RutaCargoTestFactory.customer('Globex');
    Shipment__c own = RutaCargoTestFactory.insertShipment(
      u.AccountId,
      'In transit'
    );
    Shipment__c other = RutaCargoTestFactory.insertShipment(
      globex.Id,
      'In transit'
    );
    System.runAs(u) {
      CustomerShipmentController.ShipmentDetail d = CustomerShipmentController.getMyShipment(
        own.Name
      );
      Assert.areEqual(own.Name, d.trackingNumber);
      Assert.areEqual('In transit', d.status);
      Assert.areEqual(171, d.price);
      Assert.areEqual('Calle Fresno 214', d.pickupAddress);
      Assert.areEqual('Lucía Hernández', d.recipientName);
      Assert.areEqual('Café de grano', d.packageDescription);
      String json = JSON.serialize(d).toLowerCase();
      Assert.isFalse(
        json.contains('internal only') ||
          json.contains('carrier') ||
          json.contains('margin')
      );
      try {
        CustomerShipmentController.getMyShipment(other.Name);
        Assert.fail('BR-07: another customer\'s shipment must not be visible');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('could not find'));
      }
    }
  }

  @IsTest
  static void triggerDefaultsNewShipments() {
    Account a = RutaCargoTestFactory.customer('Acme');
    Shipment__c s = new Shipment__c(Account__c = a.Id);
    insert s;
    s = [
      SELECT Name, Status__c, Reschedule_Count__c, Last_Update__c
      FROM Shipment__c
      WHERE Id = :s.Id
    ];
    Assert.areEqual('Requested', s.Status__c); // BR-09
    Assert.areEqual(0, s.Reschedule_Count__c);
    Assert.isNotNull(s.Last_Update__c);
    Assert.isTrue(Pattern.matches('RC[0-9]{9}', s.Name));
  }
}
