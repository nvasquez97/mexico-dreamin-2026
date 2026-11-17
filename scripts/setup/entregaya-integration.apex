// Setup for AC-004.6 (odd/tasks/req-004-carrier-status.md, S4, B8): the EntregaYa
// integration user. Users, license and permission set assignments and group
// memberships are data, not metadata, so they are set here, not in force-app.
// Run it with scripts/setup/entregaya-integration.sh <org-alias>, which also
// deploys the External Client App policies that name this user.
//
// In one transaction (B8: the user and its "Salesforce API Integration"
// permission set license are created in the same step):
//   1. the user entregaya-integration@<org id, lower case>.rutacargo.dev, created
//      when missing: profile "Minimum Access - API Only Integrations" (Salesforce
//      Integration license), email noreply@example.com, time zone
//      America/Mexico_City; no password and no welcome email;
//   2. the "Salesforce API Integration" permission set license;
//   3. the permission set RutaCargo_EntregaYa_Integration;
//   4. membership of the public group RutaCargo_EntregaYa_Integration.
// Idempotent: each step runs only when missing. It refuses an org that is not a
// sandbox or scratch org (Organization.IsSandbox), and it refuses to touch an
// existing user with that username that is inactive or has another profile (the
// owner decides). It prints what it did, never a secret.
final String PROFILE_NAME = 'Minimum Access - API Only Integrations';
final String API_INTEGRATION_PSL = 'SalesforceAPIIntegrationPsl';
final String PERMISSION_SET = 'RutaCargo_EntregaYa_Integration';
final String GROUP_NAME = 'RutaCargo_EntregaYa_Integration';
final String TIME_ZONE = 'America/Mexico_City';
final String EMAIL = 'noreply@example.com';

Organization org = [SELECT Id, IsSandbox FROM Organization LIMIT 1];
if (!org.IsSandbox) {
    throw new IllegalArgumentException('entregaya-integration: refused, the org is not a sandbox or scratch org');
}
String username = 'entregaya-integration@' + String.valueOf(org.Id).toLowerCase() + '.rutacargo.dev';

List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :PROFILE_NAME LIMIT 1];
List<PermissionSetLicense> licenses = [
    SELECT Id FROM PermissionSetLicense WHERE DeveloperName = :API_INTEGRATION_PSL LIMIT 1
];
List<PermissionSet> permissionSets = [
    SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET AND NamespacePrefix = null LIMIT 1
];
List<Group> groups = [SELECT Id FROM Group WHERE DeveloperName = :GROUP_NAME AND Type = 'Regular' LIMIT 1];
if (profiles.isEmpty() || licenses.isEmpty() || permissionSets.isEmpty() || groups.isEmpty()) {
    throw new IllegalArgumentException('entregaya-integration: missing profile, permission set license, '
        + 'permission set or group; deploy force-app first');
}

List<User> existing = [SELECT Id, IsActive, ProfileId FROM User WHERE Username = :username LIMIT 1];
User integration;
if (existing.isEmpty()) {
    integration = new User(
        Username = username,
        FirstName = 'EntregaYa',
        LastName = 'Integration',
        Alias = 'eyaint',
        CommunityNickname = 'entregaya.integration',
        Email = EMAIL,
        ProfileId = profiles[0].Id,
        TimeZoneSidKey = TIME_ZONE,
        LocaleSidKey = 'es_MX',
        LanguageLocaleKey = 'en_US',
        EmailEncodingKey = 'UTF-8'
    );
    insert integration;
    System.debug(LoggingLevel.INFO, 'entregaya-integration: user created');
} else {
    integration = existing[0];
    if (!integration.IsActive || integration.ProfileId != profiles[0].Id) {
        throw new IllegalArgumentException('entregaya-integration: refused, the user exists but is inactive '
            + 'or has another profile; the owner decides');
    }
    System.debug(LoggingLevel.INFO, 'entregaya-integration: user already exists');
}

if ([SELECT COUNT() FROM PermissionSetLicenseAssign
        WHERE AssigneeId = :integration.Id AND PermissionSetLicenseId = :licenses[0].Id] == 0) {
    insert new PermissionSetLicenseAssign(AssigneeId = integration.Id, PermissionSetLicenseId = licenses[0].Id);
    System.debug(LoggingLevel.INFO, 'entregaya-integration: permission set license ' + API_INTEGRATION_PSL + ' assigned');
} else {
    System.debug(LoggingLevel.INFO, 'entregaya-integration: permission set license ' + API_INTEGRATION_PSL + ' already assigned');
}

if ([SELECT COUNT() FROM PermissionSetAssignment
        WHERE AssigneeId = :integration.Id AND PermissionSetId = :permissionSets[0].Id] == 0) {
    insert new PermissionSetAssignment(AssigneeId = integration.Id, PermissionSetId = permissionSets[0].Id);
    System.debug(LoggingLevel.INFO, 'entregaya-integration: permission set ' + PERMISSION_SET + ' assigned');
} else {
    System.debug(LoggingLevel.INFO, 'entregaya-integration: permission set ' + PERMISSION_SET + ' already assigned');
}

if ([SELECT COUNT() FROM GroupMember WHERE GroupId = :groups[0].Id AND UserOrGroupId = :integration.Id] == 0) {
    insert new GroupMember(GroupId = groups[0].Id, UserOrGroupId = integration.Id);
    System.debug(LoggingLevel.INFO, 'entregaya-integration: added to group ' + GROUP_NAME);
} else {
    System.debug(LoggingLevel.INFO, 'entregaya-integration: already in group ' + GROUP_NAME);
}
