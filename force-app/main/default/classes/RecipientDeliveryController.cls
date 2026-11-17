/**
 * Guest-facing entry points for REQ-002 and REQ-003. All rules live in RecipientDeliveryService.
 * Results are returned (not thrown) so the failed-attempt counter is not rolled back.
 */
public without sharing class RecipientDeliveryController {
  @AuraEnabled
  public static RecipientDeliveryService.Result getDeliveryDetails(
    String trackingNumber,
    String postalCode
  ) {
    return RecipientDeliveryService.getDetails(trackingNumber, postalCode);
  }

  @AuraEnabled
  public static RecipientDeliveryService.ProofResult downloadProofOfDelivery(
    String trackingNumber,
    String postalCode
  ) {
    return RecipientDeliveryService.getProof(trackingNumber, postalCode);
  }

  @AuraEnabled
  public static RecipientDeliveryService.Result rescheduleDelivery(
    String trackingNumber,
    String postalCode,
    Date newDate,
    String deliveryInstructions
  ) {
    return RecipientDeliveryService.reschedule(
      trackingNumber,
      postalCode,
      newDate,
      deliveryInstructions
    );
  }
}
