/**
 * Builds AuraHandledExceptions whose message reaches the LWC (setMessage makes getMessage()
 * return the friendly text in Apex tests too).
 */
public inherited sharing class RutaCargoErrors {
  public static AuraHandledException aura(String message) {
    AuraHandledException e = new AuraHandledException(message);
    e.setMessage(message);
    return e;
  }
}
