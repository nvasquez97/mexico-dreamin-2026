/**
 * Tests for DeliveryController.reschedule, run as the real site guest.
 * Covers AC-003.1 to AC-003.5 and BR-02. Today is fixed to Tuesday
 * 2026-11-17 in Mexico City; the original estimated date is 2026-11-23,
 * so the valid window is 2026-11-18 to 2026-11-30.
 */
@IsTest
private class RescheduleDeliveryTest {
    private static final String POSTAL_CODE = '64000';
    private static final Datetime TUESDAY_NOON_MX = Datetime.newInstanceGmt(2026, 11, 17, 18, 0, 0);
    private static final Date ORIGINAL_ESTIMATE = Date.newInstance(2026, 11, 23);

    @TestSetup
    static void setup() {
        Account acme = TestDataFactory.buildCustomerAccount('Acme Test');
        Database.insert(acme, AccessLevel.SYSTEM_MODE);
        List<Shipment__c> shipments = new List<Shipment__c>();
        for (String status : new List<String>{ 'Picked up', 'In transit', 'Requested', 'Out for delivery', 'Delivered', 'Exception' }) {
            shipments.add(TestDataFactory.buildShipment(acme.Id, status));
        }
        Database.insert(shipments, AccessLevel.SYSTEM_MODE);
    }

    private static Shipment__c loadShipment(String status) {
        return [
            SELECT Id, Name, Estimated_Delivery__c, Original_Estimated_Delivery__c, Delivery_Instructions__c, Reschedule_Count__c
            FROM Shipment__c WHERE Status__c = :status WITH SYSTEM_MODE LIMIT 1
        ];
    }

    private static DeliveryController.DeliveryResponse rescheduleAsGuest(String trackingNumber, String postalCode, Date newDate, String instructions) {
        BusinessCalendar.nowOverride = TUESDAY_NOON_MX;
        DeliveryController.DeliveryResponse response;
        System.runAs(TestDataFactory.getSiteGuestUser()) {
            response = DeliveryController.reschedule(trackingNumber, postalCode, newDate, instructions);
        }
        return response;
    }

    // Covers AC-003.1, AC-003.5: new date and instructions are saved and the new date is returned.
    @IsTest
    static void shouldSaveNewDateAndInstructions_WhenInTransit() {
        Shipment__c shipment = loadShipment('In transit');
        Test.startTest();
        DeliveryController.DeliveryResponse response = rescheduleAsGuest(shipment.Name, POSTAL_CODE, Date.newInstance(2026, 11, 26), 'Leave with the doorman');
        Test.stopTest();
        Assert.isTrue(response.success, 'Rescheduled: ' + response.message);
        Assert.areEqual(Date.newInstance(2026, 11, 26), response.details.estimatedDelivery, 'New date shown');
        Shipment__c saved = loadShipment('In transit');
        Assert.areEqual(Date.newInstance(2026, 11, 26), saved.Estimated_Delivery__c, 'New date saved');
        Assert.areEqual('Leave with the doorman', saved.Delivery_Instructions__c, 'Instructions saved');
        Assert.areEqual(1, saved.Reschedule_Count__c, 'Count incremented');
        Assert.areEqual(ORIGINAL_ESTIMATE, saved.Original_Estimated_Delivery__c, 'Original date kept');
    }

    // Covers AC-003.3: Picked up shipments can be rescheduled.
    @IsTest
    static void shouldReschedule_WhenPickedUp() {
        DeliveryController.DeliveryResponse response = rescheduleAsGuest(loadShipment('Picked up').Name, POSTAL_CODE, Date.newInstance(2026, 11, 18), 'Afternoon');
        Assert.isTrue(response.success, 'Rescheduled: ' + response.message);
    }

    // Covers AC-003.3: any other status is rejected and nothing changes.
    @IsTest
    static void shouldReject_WhenStatusNotReschedulable() {
        for (String status : new List<String>{ 'Requested', 'Out for delivery', 'Delivered', 'Exception' }) {
            DeliveryController.DeliveryResponse response = rescheduleAsGuest(loadShipment(status).Name, POSTAL_CODE, Date.newInstance(2026, 11, 26), 'x');
            Assert.isFalse(response.success, status + ' must be rejected');
            Assert.areEqual('Only shipments that are picked up or in transit can be rescheduled.', response.message, 'Message for ' + status);
            Assert.areEqual(ORIGINAL_ESTIMATE, loadShipment(status).Estimated_Delivery__c, 'Date unchanged for ' + status);
        }
    }

    // Covers AC-003.2: the next day is the earliest valid date.
    @IsTest
    static void shouldAccept_WhenNewDateIsTomorrow() {
        DeliveryController.DeliveryResponse response = rescheduleAsGuest(loadShipment('In transit').Name, POSTAL_CODE, Date.newInstance(2026, 11, 18), null);
        Assert.isTrue(response.success, 'Tomorrow accepted: ' + response.message);
    }

    // Covers AC-003.2: today is rejected.
    @IsTest
    static void shouldReject_WhenNewDateIsToday() {
        DeliveryController.DeliveryResponse response = rescheduleAsGuest(loadShipment('In transit').Name, POSTAL_CODE, Date.newInstance(2026, 11, 17), null);
        Assert.isFalse(response.success, 'Today rejected');
        Assert.isTrue(response.message.startsWith('Choose a date between'), 'Message: ' + response.message);
    }

    // Covers AC-003.2: original estimated date + 7 is the last valid date; + 8 is rejected.
    @IsTest
    static void shouldReject_WhenMoreThanSevenDaysAfterOriginalEstimate() {
        String tracking = loadShipment('In transit').Name;
        DeliveryController.DeliveryResponse tooLate = rescheduleAsGuest(tracking, POSTAL_CODE, Date.newInstance(2026, 12, 1), null);
        Assert.isFalse(tooLate.success, 'Day 8 rejected');
        DeliveryController.DeliveryResponse lastDay = rescheduleAsGuest(tracking, POSTAL_CODE, Date.newInstance(2026, 11, 30), null);
        Assert.isTrue(lastDay.success, 'Day 7 accepted: ' + lastDay.message);
    }

    // Covers AC-003.2: the window stays anchored to the ORIGINAL estimate after a first reschedule.
    @IsTest
    static void shouldKeepWindowAnchoredToOriginalDate_WhenRescheduledBefore() {
        String tracking = loadShipment('In transit').Name;
        Assert.isTrue(rescheduleAsGuest(tracking, POSTAL_CODE, Date.newInstance(2026, 11, 30), null).success, 'First reschedule');
        DeliveryController.DeliveryResponse second = rescheduleAsGuest(tracking, POSTAL_CODE, Date.newInstance(2026, 12, 4), null);
        Assert.isFalse(second.success, 'Window does not slide with the new date');
    }

    // Covers AC-003.4: a third reschedule is rejected.
    @IsTest
    static void shouldReject_WhenRescheduledTwiceAlready() {
        Shipment__c shipment = loadShipment('In transit');
        shipment.Reschedule_Count__c = 2;
        Database.update(shipment, AccessLevel.SYSTEM_MODE);
        DeliveryController.DeliveryResponse response = rescheduleAsGuest(shipment.Name, POSTAL_CODE, Date.newInstance(2026, 11, 26), null);
        Assert.isFalse(response.success, 'Third reschedule rejected');
        Assert.areEqual('This delivery has already been rescheduled 2 times.', response.message, 'Message');
    }

    // Covers AC-003.4: two reschedules in a row are allowed and counted.
    @IsTest
    static void shouldAllowSecondReschedule_WhenRescheduledOnce() {
        String tracking = loadShipment('In transit').Name;
        rescheduleAsGuest(tracking, POSTAL_CODE, Date.newInstance(2026, 11, 25), null);
        DeliveryController.DeliveryResponse second = rescheduleAsGuest(tracking, POSTAL_CODE, Date.newInstance(2026, 11, 27), null);
        Assert.isTrue(second.success, 'Second reschedule accepted: ' + second.message);
        Assert.areEqual(2, loadShipment('In transit').Reschedule_Count__c, 'Two reschedules counted');
        Assert.areEqual(0, second.details.reschedulesLeft, 'None left');
    }

    // Covers BR-02: a wrong postal code cannot reschedule.
    @IsTest
    static void shouldReject_WhenPostalCodeIsWrong() {
        DeliveryController.DeliveryResponse response = rescheduleAsGuest(loadShipment('In transit').Name, '01000', Date.newInstance(2026, 11, 26), 'x');
        Assert.areEqual('The details do not match this shipment', response.message, 'Mismatch message');
        Assert.areEqual(ORIGINAL_ESTIMATE, loadShipment('In transit').Estimated_Delivery__c, 'Date unchanged');
    }

    // Covers AC-003.1: a missing date is rejected.
    @IsTest
    static void shouldReject_WhenNewDateMissing() {
        DeliveryController.DeliveryResponse response = rescheduleAsGuest(loadShipment('In transit').Name, POSTAL_CODE, null, 'x');
        Assert.isFalse(response.success, 'Missing date rejected');
    }

    // Covers AC-003.1: instructions longer than 1,000 characters are rejected.
    @IsTest
    static void shouldReject_WhenInstructionsTooLong() {
        DeliveryController.DeliveryResponse response = rescheduleAsGuest(loadShipment('In transit').Name, POSTAL_CODE, Date.newInstance(2026, 11, 26), 'x'.repeat(1001));
        Assert.isFalse(response.success, 'Long instructions rejected');
        Assert.isTrue(response.message.contains('1,000'), 'Message: ' + response.message);
    }

    // Covers AC-003.5: the reschedule fields keep field history on, so agents see when each change was made.
    @IsTest
    static void shouldTrackHistory_OnRescheduleFields() {
        Map<String, Boolean> trackedByField = new Map<String, Boolean>();
        for (FieldDefinition field : [
            SELECT QualifiedApiName, IsFieldHistoryTracked FROM FieldDefinition
            WHERE EntityDefinition.QualifiedApiName = 'Shipment__c'
            AND QualifiedApiName IN ('Estimated_Delivery__c', 'Delivery_Instructions__c', 'Reschedule_Count__c')
        ]) {
            trackedByField.put(field.QualifiedApiName, field.IsFieldHistoryTracked);
        }
        Assert.areEqual(3, trackedByField.size(), 'All three fields found');
        for (String field : trackedByField.keySet()) {
            Assert.isTrue(trackedByField.get(field), field + ' must keep field history');
        }
    }
}
