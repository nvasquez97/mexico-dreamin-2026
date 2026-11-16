/**
 * Builds AuraHandledException instances whose message is safe to show on the
 * site. Never pass internal details (stack traces, class names, raw responses).
 */
public inherited sharing class AuraErrors {
    private AuraErrors() {}

    /**
     * @param userMessage message for the site user
     * @return an AuraHandledException that also exposes the message to Apex tests
     */
    public static AuraHandledException of(String userMessage) {
        AuraHandledException error = new AuraHandledException(userMessage);
        error.setMessage(userMessage);
        return error;
    }
}
