/** REQ-001 — Public tracking. */
@IsTest
private class PublicTrackingControllerTest {
  @TestSetup
  static void setup() {
    Account acme = RutaCargoTestFactory.customer('Acme');
    List<Shipment__c> rows = new List<Shipment__c>();
    for (Integer i = 0; i < 12; i++) {
      Shipment__c s = RutaCargoTestFactory.shipment(
        acme.Id,
        Math.mod(i, 2) == 0 ? 'In transit' : 'Delivered'
      );
      s.Customer_Reference__c = 'PO-' + i;
      rows.add(s);
    }
    insert rows;
  }

  private static List<String> trackingNumbers() {
    List<String> names = new List<String>();
    for (Shipment__c s : [SELECT Name FROM Shipment__c ORDER BY Name]) {
      names.add(s.Name);
    }
    return names;
  }

  @IsTest
  static void ac001_1_acceptsUpToTenValuesSeparatedByCommasOrLineBreaks() {
    List<String> names = trackingNumbers();
    String input =
      String.join(new List<String>{ names[0], names[1], names[2] }, ',') +
      '\n' +
      names[3] +
      '\r\n' +
      names[4];
    List<PublicTrackingController.TrackingResult> results = PublicTrackingController.track(
      'TRACKING',
      input
    );
    Assert.areEqual(5, results.size());

    List<String> ten = new List<String>();
    for (Integer i = 0; i < 10; i++) {
      ten.add(names[i]);
    }
    Assert.areEqual(
      10,
      PublicTrackingController.track('TRACKING', String.join(ten, ',')).size()
    );
  }

  @IsTest
  static void ac001_1_rejectsMoreThanTenValues() {
    List<String> names = trackingNumbers();
    try {
      PublicTrackingController.track('TRACKING', String.join(names, ','));
      Assert.fail('Expected an error for 12 values');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('up to 10'), '' + e.getMessage());
    }
  }

  @IsTest
  static void ac001_1_searchesByOrderReference() {
    List<PublicTrackingController.TrackingResult> results = PublicTrackingController.track(
      'REFERENCE',
      'PO-3, PO-4'
    );
    Assert.areEqual(2, results.size());
    Assert.isTrue(results[0].found);
    Assert.areEqual('PO-3', results[0].searchValue);
  }

  @IsTest
  static void ac001_2_returnsOnlyThePublicFields() {
    Shipment__c s = [
      SELECT
        Name,
        Status__c,
        Origin_City__c,
        Destination_City__c,
        Last_Location__c,
        Last_Update__c,
        Estimated_Delivery__c
      FROM Shipment__c
      ORDER BY Name
      LIMIT 1
    ];
    PublicTrackingController.TrackingResult r = PublicTrackingController.track(
      'TRACKING',
      s.Name
    )[0];
    Assert.isTrue(r.found);
    Assert.areEqual(s.Name, r.trackingNumber);
    Assert.areEqual(s.Status__c, r.status);
    Assert.areEqual(s.Origin_City__c, r.originCity);
    Assert.areEqual(s.Destination_City__c, r.destinationCity);
    Assert.areEqual(s.Last_Location__c, r.lastLocation);
    Assert.areEqual(s.Last_Update__c, r.lastUpdate);
    Assert.areEqual(s.Estimated_Delivery__c, r.estimatedDelivery);

    // BR-01 / BR-02 / BR-03: nothing else leaves the server.
    String json = JSON.serialize(r).toLowerCase();
    for (
      String forbidden : new List<String>{
        'recipient',
        'price',
        'cost',
        'margin',
        'notes',
        'postal',
        'phone',
        'proof',
        'lucía',
        'internal only'
      }
    ) {
      Assert.isFalse(
        json.contains(forbidden),
        'Public result must not expose ' + forbidden
      );
    }
  }

  @IsTest
  static void ac001_3_valuesWithoutMatchAreNotFound() {
    String existing = trackingNumbers()[0];
    List<PublicTrackingController.TrackingResult> results = PublicTrackingController.track(
      'TRACKING',
      existing + ',RC999999999,hello'
    );
    Assert.areEqual(3, results.size());
    Assert.isTrue(results[0].found);
    Assert.isFalse(results[1].found);
    Assert.areEqual('RC999999999', results[1].searchValue);
    Assert.isFalse(results[2].found);
    Assert.isNull(results[2].status);
  }

  @IsTest
  static void ac001_4_returnsTheDataNeededToSortByStatusOrEstimatedDate() {
    List<String> names = trackingNumbers();
    List<PublicTrackingController.TrackingResult> results = PublicTrackingController.track(
      'TRACKING',
      names[0] + ',' + names[1] + ',RC999999999'
    );
    for (PublicTrackingController.TrackingResult r : results) {
      Assert.isNotNull(r.statusOrder);
      if (r.found) {
        Assert.areEqual(ShipmentConstants.statusOrder(r.status), r.statusOrder);
        Assert.isNotNull(r.estimatedDelivery);
      } else {
        Assert.isTrue(
          r.statusOrder > ShipmentConstants.STATUSES.size(),
          'Not found sorts last'
        );
      }
    }
    Assert.isTrue(
      ShipmentConstants.statusOrder('In transit') <
      ShipmentConstants.statusOrder('Delivered'),
      'Statuses sort in lifecycle order'
    );
  }

  @IsTest
  static void ac001_5_ignoresCaseAndSurroundingSpaces() {
    String name = trackingNumbers()[0];
    List<PublicTrackingController.TrackingResult> results = PublicTrackingController.track(
      'tracking',
      '   ' + name.toLowerCase() + '   ,  ' + name + '  '
    );
    Assert.areEqual(
      1,
      results.size(),
      'Duplicates differing only by case/spaces are searched once'
    );
    Assert.isTrue(results[0].found);
    Assert.areEqual(name, results[0].trackingNumber);

    Assert.isTrue(
      PublicTrackingController.track('REFERENCE', '  po-7 ')[0].found
    );
  }

  @IsTest
  static void rejectsEmptyInputAndUnknownSearchType() {
    for (String input : new List<String>{ null, '  ', ' , \n ' }) {
      try {
        PublicTrackingController.track('TRACKING', input);
        Assert.fail('Expected an error');
      } catch (AuraHandledException e) {
        Assert.isTrue(e.getMessage().contains('at least one'));
      }
    }
    try {
      PublicTrackingController.track('EMAIL', 'x');
      Assert.fail('Expected an error');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('Choose'));
    }
  }
}
