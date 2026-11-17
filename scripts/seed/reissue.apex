// Sanctioned reissue of the delivery access codes of the 120 seeded shipments
// (AC-F.18, odd/tasks/foundation.md). Run it only through
// scripts/seed/seed.sh --reissue-codes <org-alias>, which refuses to run when
// .seed-output/access-codes.csv already exists, writes the new codes to that
// git-ignored file and deletes this run's debug logs.
//
// - Changes only the access codes: one DeliveryAccessCode.reissueCodes call
//   (user mode, the running user needs Edit on the shipments) gives each of the
//   120 shipments a new code and a new salted hash; the previous codes stop
//   working. It never inserts or deletes anything.
// - Refuses (throws, nothing changes) unless exactly the 120 seeded shipments
//   RC000001001-RC000001120 of Abarrotes Acme and Globex Farma exist, and rolls
//   everything back unless one new code comes back for each of them.
// - Each new clear code is printed once, as SEEDCODE:<tracking>:<code>, only
//   after everything succeeded. The separator is ":" because the platform
//   writes "|" inside a debug message as "&#124;".

public class ReissueException extends Exception {}

final List<String> CUSTOMERS = new List<String>{ 'Abarrotes Acme', 'Globex Farma' };
final Integer EXPECTED = 120;

List<Shipment__c> shipments = [
    SELECT Id, Name
    FROM Shipment__c
    WHERE Account__r.Name IN :CUSTOMERS AND Name >= 'RC000001001' AND Name <= 'RC000001120'
    WITH USER_MODE
    ORDER BY Name
];
if (shipments.size() != EXPECTED) {
    throw new ReissueException('found ' + shipments.size() + ' of ' + EXPECTED
        + ' seeded shipments RC000001001-RC000001120; load the data with scripts/seed/seed.sh first');
}

Map<Id, String> codes = DeliveryAccessCode.reissueCodes(new Map<Id, Shipment__c>(shipments).keySet());
if (codes.size() != EXPECTED) {
    throw new ReissueException('reissueCodes returned ' + codes.size() + ' of ' + EXPECTED + ' codes; nothing was changed');
}

for (Shipment__c shipment : shipments) {
    System.debug('SEEDCODE:' + shipment.Name + ':' + codes.get(shipment.Id));
}
System.debug('SEEDREISSUE:reissued:' + codes.size());
