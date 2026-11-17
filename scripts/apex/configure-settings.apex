// RutaCargo — org default of RutaCargo_Settings__c (run after configure-org.apex, separate transaction).
RutaCargo_Settings__c settings = RutaCargo_Settings__c.getOrgDefaults();
if (settings == null || settings.Id == null) {
  settings = new RutaCargo_Settings__c(
    SetupOwnerId = UserInfo.getOrganizationId()
  );
}
settings.Account_Owner_Id__c = UserInfo.getUserId();
upsert settings;
System.debug(
  'Self-registered accounts will be owned by ' + UserInfo.getUserName()
);
