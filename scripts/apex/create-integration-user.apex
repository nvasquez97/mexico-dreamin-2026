// Creates the run-as user for the inbound EntregaYa OAuth client-credentials flow and gives it the
// RutaCargo_EntregaYa_Integration permission set (class access to the status service + EntregaYa_Status_Update).
// Select this user as "Run As" in Setup > External Client App Manager > EntregaYa Status > Policies (manual step).
String username = 'entregaya.integration@rutacargo.example.com';
if ([SELECT COUNT() FROM User WHERE Username = :username] > 0) {
    System.debug('Integration user already exists.');
    return;
}
Profile profile = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - API Only Integrations' LIMIT 1];
User integration = new User(
    Username = username, Email = 'jhony.atehortua@adaptus.com', FirstName = 'EntregaYa', LastName = 'Integration',
    Alias = 'entyaint', ProfileId = profile.Id, TimeZoneSidKey = 'America/Mexico_City', LocaleSidKey = 'en_US',
    EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US'
);
insert integration;
insert new PermissionSetAssignment(
    AssigneeId = integration.Id,
    PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'RutaCargo_EntregaYa_Integration' LIMIT 1].Id
);
System.debug('Integration user created: ' + username);
