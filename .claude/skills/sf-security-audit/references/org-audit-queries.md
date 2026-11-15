# Org audit queries (read-only)

Source metadata cannot show **who** holds a permission, live site settings, or Health Check results. Run
these against the target org when one is in scope. All are read-only `SELECT`s.

```bash
ORG=<alias>
q()  { sf data query --target-org "$ORG" --json --query "$1"; }
qt() { sf data query --target-org "$ORG" --json --use-tooling-api --query "$1"; }
```

Some objects/fields vary by edition and release. If a query errors on an unknown field, drop that field and
note it under "Not covered" in the report — never guess the result.

## P6 / P7 — Admin-level access holders

```sql
-- Active users holding MAD/VAD via profile OR permission set (one row per grant)
SELECT Assignee.Username, Assignee.Name, Assignee.Profile.Name, Assignee.LastLoginDate,
       PermissionSet.Name, PermissionSet.IsOwnedByProfile,
       PermissionSet.PermissionsModifyAllData, PermissionSet.PermissionsViewAllData
FROM PermissionSetAssignment
WHERE Assignee.IsActive = true
  AND (PermissionSet.PermissionsModifyAllData = true OR PermissionSet.PermissionsViewAllData = true)

-- Admin-equivalent count by profile
SELECT Profile.Name, COUNT(Id) total FROM User
WHERE IsActive = true AND Profile.PermissionsModifyAllData = true GROUP BY Profile.Name

-- Total active users (denominator for the admin ratio)
SELECT COUNT() FROM User WHERE IsActive = true AND UserType = 'Standard'

-- Dormant admins
SELECT Username, Profile.Name, LastLoginDate FROM User
WHERE IsActive = true AND Profile.PermissionsModifyAllData = true
  AND (LastLoginDate < LAST_N_DAYS:90 OR LastLoginDate = null)

-- Custom permission sets granting high-risk system permissions (P6)
SELECT Name, Label, PermissionsModifyAllData, PermissionsViewAllData, PermissionsModifyMetadata,
       PermissionsCustomizeApplication, PermissionsAuthorApex, PermissionsManageUsers,
       PermissionsAssignPermissionSets, PermissionsViewEncryptedData
FROM PermissionSet
WHERE IsOwnedByProfile = false
  AND (PermissionsModifyAllData = true OR PermissionsViewAllData = true OR PermissionsModifyMetadata = true
       OR PermissionsCustomizeApplication = true OR PermissionsAuthorApex = true OR PermissionsManageUsers = true
       OR PermissionsAssignPermissionSets = true OR PermissionsViewEncryptedData = true)
```

## P5 — View All / Modify All on objects

```sql
SELECT Parent.Name, Parent.IsOwnedByProfile, Parent.Profile.Name, SobjectType,
       PermissionsViewAllRecords, PermissionsModifyAllRecords, PermissionsViewAllFields
FROM ObjectPermissions
WHERE PermissionsViewAllRecords = true OR PermissionsModifyAllRecords = true OR PermissionsViewAllFields = true
```
Then count assignees for each non-admin permission set:
`SELECT PermissionSet.Name, COUNT(Id) FROM PermissionSetAssignment WHERE PermissionSet.Name IN (...) GROUP BY PermissionSet.Name`

## P3 — Org-wide defaults

```sql
SELECT QualifiedApiName, Label, InternalSharingModel, ExternalSharingModel
FROM EntityDefinition WHERE IsCustomizable = true ORDER BY QualifiedApiName LIMIT 2000
```
Filter client-side for `Read`, `ReadWrite`, `ReadWriteTransfer`, `FullAccess` (internal) and anything other
than `Private` / `ControlledByParent` for external. EntityDefinition does not support queryMore: page with
`WHERE QualifiedApiName > '<last>'` if 2000 rows come back.

## P4 — FLS on sensitive fields

```sql
SELECT Parent.Name, Parent.IsOwnedByProfile, SobjectType, Field, PermissionsRead, PermissionsEdit
FROM FieldPermissions
WHERE Field IN ('Contact.SSN__c', '...')          -- the sensitive fields identified in source/data classification
```

## P1 — Guest users

```sql
SELECT Id, Name, Subdomain, UrlPathPrefix, Status, SiteType, GuestUserId FROM Site
SELECT Id, Name, Status, UrlPathPrefix FROM Network
SELECT Id, Username, Profile.Name, IsActive FROM User WHERE UserType = 'Guest'

SELECT Id, Name, PermissionsApiEnabled, PermissionsViewAllUsers, PermissionsRunFlow
FROM Profile WHERE UserLicense.Name = 'Guest User License'

SELECT Parent.Profile.Name, SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit,
       PermissionsDelete, PermissionsViewAllRecords, PermissionsModifyAllRecords
FROM ObjectPermissions WHERE Parent.Profile.UserLicense.Name = 'Guest User License'

SELECT Parent.Profile.Name, SobjectType, Field, PermissionsRead, PermissionsEdit
FROM FieldPermissions WHERE Parent.Profile.UserLicense.Name = 'Guest User License'

-- Apex classes / VF pages / flows granted to guest profiles (also check permission sets assigned to guest users)
SELECT Parent.Profile.Name, SetupEntityType, SetupEntityId
FROM SetupEntityAccess
WHERE Parent.Profile.UserLicense.Name = 'Guest User License'
  AND SetupEntityType IN ('ApexClass', 'ApexPage', 'FlowDefinition')
-- resolve names: SELECT Id, Name, ApiVersion FROM ApexClass WHERE Id IN (...)

-- Permission sets assigned directly to guest users
SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment
WHERE Assignee.UserType = 'Guest' AND PermissionSet.IsOwnedByProfile = false
```
Settings to confirm (Setup UI or retrieved `Sharing`/`Communities` settings), per site: Secure guest user
record access, guest access to public APIs off, "Let guest users see other members" off, "Hide first and last
name fields in SOAP API for site users" on, guest sharing rules list.

## P2 / P9 — Integrations and credentials

```sql
SELECT DeveloperName, MasterLabel, Endpoint, PrincipalType FROM NamedCredential
SELECT Name, OptionsAllowAdminApprovedUsersOnly, OptionsRefreshTokenValidityMetric FROM ConnectedApplication
SELECT AppName, User.Username, LastUsedDate, UseCount FROM OauthToken ORDER BY LastUsedDate DESC LIMIT 200
```
```sql
-- Tooling API (qt)
SELECT SiteName, EndpointUrl, DisableProtocolSecurity, IsActive FROM RemoteProxy
SELECT Name, ApiVersion, NamespacePrefix FROM ApexClass WHERE NamespacePrefix = null ORDER BY ApiVersion
```
Custom settings that may hold credentials: list them with
`SELECT QualifiedApiName FROM EntityDefinition WHERE IsCustomSetting = true`, then inspect their fields
(retrieved metadata or `FieldDefinition WHERE EntityDefinition.QualifiedApiName = '<name>'` via tooling).
**Do not query the values** of suspected secret fields; report the field, not the secret.

## X10 — Security Health Check & audit trail

```sql
-- Tooling API (qt)
SELECT Score FROM SecurityHealthCheck
SELECT RiskType, Setting, SettingGroup, OrgValue, StandardValue
FROM SecurityHealthCheckRisks WHERE RiskType IN ('HIGH_RISK', 'MEDIUM_RISK')
```
```sql
SELECT CreatedDate, CreatedBy.Username, Action, Section, Display
FROM SetupAuditTrail WHERE CreatedDate = LAST_N_DAYS:90 ORDER BY CreatedDate DESC LIMIT 500
```
Look for permission/profile/sharing/site changes made outside the deployment pipeline.
