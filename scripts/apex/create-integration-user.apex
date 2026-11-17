// RutaCargo — EntregaYa integration user (BR-04). Salesforce Integration license, API only,
// with the "Salesforce API Integration" permission set license and the EntregaYa_Integration
// permission set (access to the status-updates Apex REST class only).
// This user is the "run as" user of the EntregaYa External Client App (client credentials flow).
String username =
  'entregaya.integration@rutacargo-' +
  String.valueOf(UserInfo.getOrganizationId()).left(15).toLowerCase() +
  '.example';
List<User> existing = [SELECT Id FROM User WHERE Username = :username];
User integrationUser;
if (existing.isEmpty()) {
  Profile p = [
    SELECT Id
    FROM Profile
    WHERE UserLicense.Name = 'Salesforce Integration'
    LIMIT 1
  ];
  integrationUser = new User(
    Username = username,
    Email = 'entregaya.integration@rutacargo.example',
    FirstName = 'EntregaYa',
    LastName = 'Integration',
    Alias = 'entregay',
    ProfileId = p.Id,
    LanguageLocaleKey = 'en_US',
    LocaleSidKey = 'es_MX',
    TimeZoneSidKey = 'America/Mexico_City',
    EmailEncodingKey = 'UTF-8'
  );
  insert integrationUser;
} else {
  integrationUser = existing[0];
}
PermissionSetLicense psl = [
  SELECT Id
  FROM PermissionSetLicense
  WHERE DeveloperName = 'SalesforceAPIIntegrationPsl'
  LIMIT 1
];
if (
  [
    SELECT COUNT()
    FROM PermissionSetLicenseAssign
    WHERE AssigneeId = :integrationUser.Id AND PermissionSetLicenseId = :psl.Id
  ] == 0
) {
  insert new PermissionSetLicenseAssign(
    AssigneeId = integrationUser.Id,
    PermissionSetLicenseId = psl.Id
  );
}
PermissionSet ps = [
  SELECT Id
  FROM PermissionSet
  WHERE Name = 'EntregaYa_Integration'
  LIMIT 1
];
if (
  [
    SELECT COUNT()
    FROM PermissionSetAssignment
    WHERE AssigneeId = :integrationUser.Id AND PermissionSetId = :ps.Id
  ] == 0
) {
  insert new PermissionSetAssignment(
    AssigneeId = integrationUser.Id,
    PermissionSetId = ps.Id
  );
}
System.debug('EntregaYa integration user: ' + username);
