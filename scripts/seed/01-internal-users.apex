// RutaCargo seed, step 1 of 3 (setup objects only). Idempotent.
// - Gives the running admin the RutaCargo Operations role (portal account owners need a role)
//   and the RutaCargo_Support_Agent permission set.
// - Gives the site guest user the RutaCargo_Guest permission set.
// - Creates the EntregaYa integration user with only the EntregaYa_Integration permission set.
Id adminId = UserInfo.getUserId();
UserRole operations = [SELECT Id FROM UserRole WHERE DeveloperName = 'RutaCargo_Operations' LIMIT 1];
User admin = [SELECT Id, UserRoleId FROM User WHERE Id = :adminId];
if (admin.UserRoleId == null) {
    admin.UserRoleId = operations.Id;
    update admin;
}

Map<String, Id> permSetIds = new Map<String, Id>();
for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN ('RutaCargo_Support_Agent', 'RutaCargo_Guest', 'EntregaYa_Integration')]) {
    permSetIds.put(ps.Name, ps.Id);
}
User guest = [SELECT Id FROM User WHERE Profile.Name = 'RutaCargo Profile' AND UserType = 'Guest' LIMIT 1];

String integrationUsername = 'entregaya.integration@' + UserInfo.getOrganizationId().toLowerCase() + '.rutacargo.example';
List<User> integrationUsers = [SELECT Id FROM User WHERE Username = :integrationUsername];
User integration;
if (integrationUsers.isEmpty()) {
    Profile apiOnly = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - API Only Integrations' LIMIT 1];
    integration = new User(
        ProfileId = apiOnly.Id, Username = integrationUsername, Email = 'integrations@rutacargo.example.com',
        FirstName = 'EntregaYa', LastName = 'Integration', Alias = 'eyint',
        TimeZoneSidKey = 'America/Mexico_City', LocaleSidKey = 'en_US', LanguageLocaleKey = 'en_US', EmailEncodingKey = 'UTF-8'
    );
    insert integration;
} else {
    integration = integrationUsers[0];
}

Map<Id, Id> wanted = new Map<Id, Id>{
    adminId => permSetIds.get('RutaCargo_Support_Agent'),
    guest.Id => permSetIds.get('RutaCargo_Guest'),
    integration.Id => permSetIds.get('EntregaYa_Integration')
};
Set<String> existing = new Set<String>();
for (PermissionSetAssignment psa : [SELECT AssigneeId, PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId IN :wanted.keySet()]) {
    existing.add('' + psa.AssigneeId + psa.PermissionSetId);
}
List<PermissionSetAssignment> toAssign = new List<PermissionSetAssignment>();
for (Id userId : wanted.keySet()) {
    if (!existing.contains('' + userId + wanted.get(userId))) {
        toAssign.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = wanted.get(userId)));
    }
}
insert toAssign;

// The Salesforce Integration license needs the API integration permission set license.
List<PermissionSetLicense> apiPsl = [SELECT Id FROM PermissionSetLicense WHERE DeveloperName = 'SalesforceAPIIntegrationPsl' LIMIT 1];
if (!apiPsl.isEmpty() && [SELECT COUNT() FROM PermissionSetLicenseAssign WHERE AssigneeId = :integration.Id AND PermissionSetLicenseId = :apiPsl[0].Id] == 0) {
    insert new PermissionSetLicenseAssign(AssigneeId = integration.Id, PermissionSetLicenseId = apiPsl[0].Id);
}
System.debug('SEED1 OK integration user: ' + integrationUsername + ' assignments added: ' + toAssign.size());
