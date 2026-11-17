// Setup for AC-F.9 (odd/tasks/foundation.md): the RutaCargo site guest user
// works in the America/Mexico_City time zone (BR-06, assumption A5).
// The guest user record is data, not metadata, so it is set here, not in force-app.
// Idempotent: it finds the guest user through the site (never a hard-coded Id)
// and updates only when the time zone differs. Run it with
// scripts/setup/site-guest-user.sh <org-alias>.
final String SITE_NAME = 'RutaCargo';
final String TIME_ZONE = 'America/Mexico_City';

List<Site> sites = [
    SELECT GuestUserId
    FROM Site
    WHERE Name = :SITE_NAME AND SiteType = 'ChatterNetwork'
    LIMIT 1
];
if (sites.isEmpty() || sites[0].GuestUserId == null) {
    throw new IllegalArgumentException('Site ' + SITE_NAME + ' or its guest user was not found');
}

User guest = [SELECT Id, TimeZoneSidKey FROM User WHERE Id = :sites[0].GuestUserId];
if (guest.TimeZoneSidKey == TIME_ZONE) {
    System.debug(LoggingLevel.INFO, 'site-guest-user: time zone already ' + TIME_ZONE + ', nothing changed');
} else {
    guest.TimeZoneSidKey = TIME_ZONE;
    update guest;
    System.debug(LoggingLevel.INFO, 'site-guest-user: time zone set to ' + TIME_ZONE);
}
