// RutaCargo — one-time org configuration (idempotent). Run as an administrator:
//   sf apex run -o <alias> -f scripts/apex/configure-org.apex
// 1) The running admin gets the "RutaCargo Operations" role: owners of customer accounts need a role
//    so that site users can be created under those accounts.
// 2) RutaCargo_Settings__c.Account_Owner_Id__c = that admin (owner of self-registered accounts).
// 3) The site guest user gets the "RutaCargo Site Guest" permission set.
// Setup objects (User, PermissionSetAssignment) and the custom setting are updated in this order
// without mixing in other non-setup DML.
UserRole role = [
  SELECT Id
  FROM UserRole
  WHERE DeveloperName = 'RutaCargo_Operations'
  LIMIT 1
];
User admin = [SELECT Id, UserRoleId FROM User WHERE Id = :UserInfo.getUserId()];
if (admin.UserRoleId == null) {
  admin.UserRoleId = role.Id;
  update admin;
  System.debug(
    'Assigned role RutaCargo Operations to ' + UserInfo.getUserName()
  );
}

List<User> guests = [
  SELECT Id
  FROM User
  WHERE
    Profile.Name = 'RutaCargo Profile'
    AND UserType = 'Guest'
    AND IsActive = TRUE
  LIMIT 1
];
PermissionSet guestPermSet = [
  SELECT Id
  FROM PermissionSet
  WHERE Name = 'RutaCargo_Site_Guest'
  LIMIT 1
];
if (
  !guests.isEmpty() &&
  [
    SELECT COUNT()
    FROM PermissionSetAssignment
    WHERE AssigneeId = :guests[0].Id AND PermissionSetId = :guestPermSet.Id
  ] == 0
) {
  insert new PermissionSetAssignment(
    AssigneeId = guests[0].Id,
    PermissionSetId = guestPermSet.Id
  );
  System.debug('Assigned RutaCargo_Site_Guest to the site guest user');
}
