// RutaCargo — test data (step 2 of 2): one site user per test customer.
// Run through scripts/setup-org.sh, which replaces __TEST_USER_PASSWORD__ with the
// TEST_USER_PASSWORD environment variable (or a random password it prints once).
// Usernames follow the same rule as self-registration (CustomerAuthController.usernameFor);
// customers log in with their email.
String password = '__TEST_USER_PASSWORD__';
Profile customerProfile = [
  SELECT Id
  FROM Profile
  WHERE Name = 'RutaCargo Customer'
  LIMIT 1
];
PermissionSet customerPermSet = [
  SELECT Id
  FROM PermissionSet
  WHERE Name = 'RutaCargo_Customer'
  LIMIT 1
];

List<Contact> contacts = [
  SELECT Id, FirstName, LastName, Email, Phone
  FROM Contact
  WHERE
    Email IN (
      'ana.lopez@abarrotes-acme.example',
      'marta.ruiz@globex-farma.example'
    )
];
Set<Id> withUser = new Set<Id>();
for (User u : [SELECT ContactId FROM User WHERE ContactId IN :contacts]) {
  withUser.add(u.ContactId);
}
List<User> users = new List<User>();
for (Contact c : contacts) {
  if (withUser.contains(c.Id)) {
    continue;
  }
  users.add(
    new User(
      ContactId = c.Id,
      ProfileId = customerProfile.Id,
      Username = CustomerAuthController.usernameFor(c.Email),
      Email = c.Email,
      FirstName = c.FirstName,
      LastName = c.LastName,
      Phone = c.Phone,
      Alias = (c.FirstName.left(1) + c.LastName.left(4)).toLowerCase(),
      CommunityNickname = c.FirstName + '.' + c.LastName.left(3) + '.rc',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'es_MX',
      TimeZoneSidKey = 'America/Mexico_City',
      EmailEncodingKey = 'UTF-8'
    )
  );
}
if (!users.isEmpty()) {
  insert users;
  List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
  for (User u : users) {
    System.setPassword(u.Id, password);
    assignments.add(
      new PermissionSetAssignment(
        AssigneeId = u.Id,
        PermissionSetId = customerPermSet.Id
      )
    );
  }
  insert assignments;
}
for (User u : [SELECT Username, Email FROM User WHERE ContactId IN :contacts]) {
  System.debug('Site user: ' + u.Email + ' (username ' + u.Username + ')');
}
