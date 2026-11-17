// Customer accounts are created by the site guest user, so they are owned by the site's default owner.
// Salesforce requires that owner to have a role before an external user can be attached to the account.
// Run once per org (see README): gives the running admin the RutaCargo Admin role.
Id roleId = [SELECT Id FROM UserRole WHERE DeveloperName = 'RutaCargo_Admin'].Id;
update new User(Id = UserInfo.getUserId(), UserRoleId = roleId);
