// RutaCargo seed, step 3 of 3 (setup objects). Idempotent.
// Creates the site users Ana López (Abarrotes Acme) and Marta Ruiz (Globex Farma) with the
// RutaCargo Customer profile and the RutaCargo_Customer permission set, and sets their password.
// __SEED_PASSWORD__ is replaced at run time by scripts/seed/seed.sh; it is never stored in the repo.
String seedPassword = '__SEED_PASSWORD__';
Profile customerProfile = [SELECT Id FROM Profile WHERE Name = 'RutaCargo Customer' LIMIT 1];
PermissionSet customerAccess = [SELECT Id FROM PermissionSet WHERE Name = 'RutaCargo_Customer' LIMIT 1];
List<Contact> people = [SELECT Id, FirstName, LastName, Email FROM Contact WHERE Email IN ('ana.lopez@abarrotes-acme.example', 'marta.ruiz@globex-farma.example')];
Set<String> usernames = new Set<String>();
for (Contact person : people) {
    usernames.add(person.Email + CustomerAuthController.USERNAME_SUFFIX);
}
Set<String> existing = new Set<String>();
for (User u : [SELECT Username FROM User WHERE Username IN :usernames]) {
    existing.add(u.Username);
}
List<User> created = new List<User>();
for (Contact person : people) {
    String username = person.Email + CustomerAuthController.USERNAME_SUFFIX;
    if (existing.contains(username)) {
        continue;
    }
    created.add(new User(
        ProfileId = customerProfile.Id, ContactId = person.Id, Username = username, Email = person.Email,
        FirstName = person.FirstName, LastName = person.LastName,
        Alias = (person.FirstName.left(1) + person.LastName).replaceAll('[^A-Za-z]', '').left(8),
        CommunityNickname = person.Email.substringBefore('@'),
        TimeZoneSidKey = 'America/Mexico_City', LocaleSidKey = 'en_US', LanguageLocaleKey = 'en_US', EmailEncodingKey = 'UTF-8'
    ));
}
insert created;
List<PermissionSetAssignment> access = new List<PermissionSetAssignment>();
for (User u : created) {
    access.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = customerAccess.Id));
}
insert access;
for (User u : [SELECT Id FROM User WHERE Username IN :usernames]) {
    System.setPassword(u.Id, seedPassword);
}
System.debug('SEED3 OK site users created: ' + created.size());
