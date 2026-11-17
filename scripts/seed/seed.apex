// RutaCargo test data (AC-F.11, odd/tasks/foundation.md; design "Test data and
// definition of done", docs/functional-design.md). Run it only through
// scripts/seed/seed.sh <org-alias>, which assigns the field permissions it needs
// (A12), keeps the access codes out of the repository and deletes this run's
// debug logs.
//
// - Idempotent: when both customers exist with 60 shipments each it changes
//   nothing; any other existing state fails without changing anything. It
//   never deletes.
// - Every query and DML runs in user mode (no system mode).
// - The 120 shipments are inserted in one DeliveryAccessCode.insertWithCodes
//   call (Acme first), so the tracking numbers are RC000001001-RC000001060
//   (Acme) and RC000001061-RC000001120 (Globex); any other numbering is rolled
//   back. The trigger starts every shipment in Requested (AC-F.15), so the
//   final statuses are set by a second DML (update).
// - Dates are relative to the run date in America/Mexico_City (BR-06).
// - Each clear access code is printed once, as SEEDCODE|<tracking>|<code>, only
//   after everything succeeded; seed.sh moves them to the git-ignored
//   .seed-output/access-codes.csv. Names, addresses, phones and emails are
//   fictional (example.com, 55-0000-xxxx).

public class SeedException extends Exception {}

final String ACME = 'Abarrotes Acme';
final String GLOBEX = 'Globex Farma';
final List<String> CUSTOMERS = new List<String>{ ACME, GLOBEX };
final Integer PER_CUSTOMER = 60;
final Integer FIRST_NUMBER = 1001;

// ─── Helpers ────────────────────────────────────────────────────────────────

// RC + 9 digits (BR-05).
String trackingNumber(Integer n) {
    return 'RC' + String.valueOf(n).leftPad(9, '0');
}

// The instant of a Mexico City wall-clock time.
Datetime mexicoCity(Date day, Integer hour, Integer minute) {
    Datetime wall = Datetime.newInstanceGmt(day, Time.newInstance(hour, minute, 0, 0));
    return wall.addSeconds(-TimeZone.getTimeZone('America/Mexico_City').getOffset(wall) / 1000);
}

String ascii(String value) {
    return value.replace('á', 'a').replace('é', 'e').replace('í', 'i')
        .replace('ó', 'o').replace('ú', 'u').replace('ñ', 'n').replace(' ', '');
}

// BR-08: Standard 120 + 18/kg, Express 220 + 30/kg, plus 1.5% of the declared value.
Decimal price(String service, Decimal kg, Decimal declared) {
    Decimal base = service == 'Express' ? 220 + 30 * kg : 120 + 18 * kg;
    return (base + declared * 0.015).setScale(2, RoundingMode.HALF_UP);
}

// ─── 1. Current state: idempotency ──────────────────────────────────────────

Map<String, List<Account>> accountsByName = new Map<String, List<Account>>{
    ACME => new List<Account>(), GLOBEX => new List<Account>()
};
for (Account existing : [SELECT Id, Name FROM Account WHERE Name IN :CUSTOMERS WITH USER_MODE]) {
    accountsByName.get(existing.Name).add(existing);
}
Map<Id, Integer> shipmentsByAccount = new Map<Id, Integer>();
for (AggregateResult row : [
    SELECT Account__c customer, COUNT(Id) total FROM Shipment__c
    WHERE Account__r.Name IN :CUSTOMERS WITH USER_MODE GROUP BY Account__c
]) {
    shipmentsByAccount.put((Id) row.get('customer'), (Integer) row.get('total'));
}

List<String> state = new List<String>();
Boolean loaded = true;
Boolean empty = true;
for (String name : CUSTOMERS) {
    List<Account> found = accountsByName.get(name);
    Integer shipments = 0;
    for (Account existing : found) {
        Integer counted = shipmentsByAccount.get(existing.Id);
        shipments += counted == null ? 0 : counted;
    }
    state.add(name + ': ' + found.size() + ' account(s), ' + shipments + ' shipment(s)');
    loaded = loaded && found.size() == 1 && shipments == PER_CUSTOMER;
    empty = empty && found.isEmpty();
}

if (loaded) {
    System.debug(LoggingLevel.INFO, 'SEED|already-loaded|' + String.join(state, '; ') + '|nothing created');
} else if (!empty) {
    throw new SeedException('partial seed state (' + String.join(state, '; ')
        + '). Nothing was changed. The seed never deletes: use a new scratch org or clean these records by hand.');
} else {
    // ─── 2. The Auto Number must still be at its start ─────────────────────
    Integer existingShipments = [SELECT COUNT() FROM Shipment__c WITH USER_MODE ALL ROWS];
    if (existingShipments > 0) {
        throw new SeedException('the org already has ' + existingShipments
            + ' Shipment__c record(s) (deleted ones included), so the next tracking number is not '
            + trackingNumber(FIRST_NUMBER) + '. Nothing was changed. Load the seed in a new scratch org.');
    }

    Datetime runAt = Datetime.now();
    Date runDate = Date.valueOf(runAt.format('yyyy-MM-dd', 'America/Mexico_City'));
    Savepoint beforeSeed = Database.setSavepoint();

    // ─── 3. Customers and contacts ─────────────────────────────────────────
    Account acmeAccount = new Account(Name = ACME, Customer_Type__c = 'Business', Credit_Risk__c = 'Low',
        Credit_Limit__c = 500000, Phone = '55-0000-1000', BillingStreet = 'Calz. Ermita Iztapalapa 1500, Bodega 12',
        BillingCity = 'Ciudad de México', BillingState = 'CDMX', BillingPostalCode = '09510', BillingCountry = 'Mexico');
    Account globexAccount = new Account(Name = GLOBEX, Customer_Type__c = 'Business', Credit_Risk__c = 'High',
        Credit_Limit__c = 150000, Phone = '33-0000-2000', BillingStreet = 'Av. Vallarta 6503, Nave 4',
        BillingCity = 'Zapopan', BillingState = 'Jalisco', BillingPostalCode = '45010', BillingCountry = 'Mexico');
    List<Account> customerAccounts = new List<Account>{ acmeAccount, globexAccount };
    Database.insert(customerAccounts, true, AccessLevel.USER_MODE);
    Database.insert(new List<Contact>{
        new Contact(AccountId = acmeAccount.Id, FirstName = 'Ana', LastName = 'López',
            Email = 'ana.lopez@example.com', Phone = '55-0000-1001', Title = 'Logistics Manager'),
        new Contact(AccountId = globexAccount.Id, FirstName = 'Marta', LastName = 'Ruiz',
            Email = 'marta.ruiz@example.com', Phone = '33-0000-2001', Title = 'Distribution Lead')
    }, true, AccessLevel.USER_MODE);

    // ─── 4. Shipments: Acme's 60, then Globex's 60, in one insert ──────────
    // City|State|Postal code|Street of a delivery point.
    List<String> destinations = new List<String>{
        'Guadalajara|JAL|44160|Av. Chapultepec Sur 480, Col. Americana',
        'Monterrey|NL|64000|Av. Juárez 1102 Pte., Col. Centro',
        'Puebla|PUE|72000|Calle 5 de Mayo 210, Col. Centro',
        'Querétaro|QRO|76000|Av. Constituyentes 45, Col. Centro',
        'León|GTO|37000|Blvd. Adolfo López Mateos 1810, Col. Centro',
        'Mérida|YUC|97000|Calle 60 No. 320, Col. Centro',
        'Toluca|MEX|50000|Av. Hidalgo 501 Pte., Col. Centro',
        'Tijuana|BC|22000|Av. Revolución 1020, Zona Centro',
        'San Luis Potosí|SLP|78000|Av. Carranza 735, Col. Tequisquiapan',
        'Aguascalientes|AGS|20000|Av. Madero 418, Zona Centro',
        'Veracruz|VER|91700|Av. Independencia 1180, Col. Centro',
        'Cancún|QROO|77500|Av. Tulum 230, SM 4',
        'Morelia|MICH|58000|Av. Madero Pte. 1250, Col. Centro',
        'Oaxaca|OAX|68000|Calle Macedonio Alcalá 402, Col. Centro',
        'Chihuahua|CHIH|31000|Av. Independencia 905, Col. Centro',
        'Hermosillo|SON|83000|Blvd. Hidalgo 72, Col. Centenario',
        'Saltillo|COAH|25000|Calle Victoria 345, Zona Centro',
        'Culiacán|SIN|80000|Av. Álvaro Obregón 560 Sur, Col. Centro',
        'Torreón|COAH|27000|Av. Morelos 1350 Pte., Col. Centro',
        'Ciudad de México|CDMX|06700|Av. Álvaro Obregón 130, Col. Roma Norte'
    };
    List<String> hubs = new List<String>{ 'Querétaro, QRO', 'Celaya, GTO', 'San Juan del Río, QRO', 'Irapuato, GTO' };
    List<String> firstNames = new List<String>{ 'Sofía', 'Diego', 'Valeria', 'Javier', 'Camila', 'Andrés', 'Lucía', 'Emilio', 'Regina', 'Tomás', 'Daniela', 'Rodrigo' };
    List<String> lastNames = new List<String>{ 'Hernández', 'García', 'Martínez', 'Ramírez', 'Torres', 'Flores', 'Morales', 'Castillo', 'Ortega', 'Navarro' };
    List<String> instructions = new List<String>{
        'Leave with the building concierge.', 'Call 15 minutes before arriving.', null,
        'Deliver at the loading dock, 9:00-14:00.', 'Ring the side door bell.', null
    };
    // Spread of the six statuses: per 10 shipments 3 Delivered, 2 In transit,
    // 2 Requested, 1 Picked up, 1 Out for delivery, 1 Exception.
    List<String> statusCycle = new List<String>{
        'Delivered', 'In transit', 'Requested', 'Delivered', 'Picked up',
        'Out for delivery', 'Delivered', 'In transit', 'Exception', 'Requested'
    };
    Map<String, List<String>> packagesByCustomer = new Map<String, List<String>>{
        ACME => new List<String>{ 'Dry groceries: 12 boxes of pasta', 'Canned vegetables, 24 units',
            'Coffee beans, 10 bags of 1 kg', 'Cooking oil, 6 bottles of 1 L', 'Rice and beans, mixed sacks', 'Spice assortment, 30 jars' },
        GLOBEX => new List<String>{ 'Vitamin supplements, sealed cartons', 'Over-the-counter analgesics, 20 boxes',
            'Nitrile gloves, 10 boxes', 'Dermatology creams, 40 tubes', 'Sterile syringe kits, 25 units', 'Digital thermometers, 15 units' }
    };
    Map<String, String> originByCustomer = new Map<String, String>{ ACME => 'Ciudad de México, CDMX', GLOBEX => 'Zapopan, JAL' };
    Map<String, String> pickupByCustomer = new Map<String, String>{
        ACME => 'Calz. Ermita Iztapalapa 1500, Bodega 12, Col. Santa Martha Acatitla, Ciudad de México, C.P. 09510',
        GLOBEX => 'Av. Vallarta 6503, Nave 4, Col. Ciudad Granja, Zapopan, Jalisco, C.P. 45010'
    };
    Map<String, String> pickupPostalByCustomer = new Map<String, String>{ ACME => '09510', GLOBEX => '45010' };
    Map<String, String> referencePrefix = new Map<String, String>{ ACME => 'ACME-PO-', GLOBEX => 'GLX-ORD-' };

    List<Shipment__c> rows = new List<Shipment__c>();
    List<String> finalStatuses = new List<String>();
    for (Integer c = 0; c < CUSTOMERS.size(); c++) {
        String customerName = CUSTOMERS[c];
        Account customer = customerAccounts[c];
        for (Integer i = 0; i < PER_CUSTOMER; i++) {
            List<String> point = destinations[Math.mod(i * 7 + c * 3, destinations.size())].split('\\|');
            if (point[0] == originByCustomer.get(customerName).substringBefore(',')) {
                point = destinations[Math.mod(i * 7 + c * 3 + 1, destinations.size())].split('\\|');
            }
            String first = firstNames[Math.mod(i + c * 5, firstNames.size())];
            String last = lastNames[Math.mod(i * 3 + c, lastNames.size())];
            String service = Math.mod(i, 3) == 0 ? 'Express' : 'Standard';
            Decimal kg = 0.5 + Math.mod(i * 7 + c * 3, 59) * 0.5;
            Decimal declared = c == 0 ? 500 + Math.mod(i * 37 + 11, 100) * 150 : 2000 + Math.mod(i * 53 + 7, 97) * 500;
            Decimal amount = price(service, kg, declared);
            Integer transitDays = service == 'Express' ? 1 + Math.mod(i, 2) : 3 + Math.mod(i, 3);
            String status = statusCycle[Math.mod(i, statusCycle.size())];

            Date pickup;
            Date estimate;
            if (status == 'Requested') {
                pickup = runDate.addDays(1 + Math.mod(i, 4));
                estimate = pickup.addDays(transitDays);
            } else if (status == 'Picked up') {
                pickup = runDate.addDays(-Math.mod(i, 2));
                estimate = pickup.addDays(transitDays);
            } else if (status == 'In transit') {
                pickup = runDate.addDays(-1 - Math.mod(i, 3));
                estimate = runDate.addDays(1 + Math.mod(i, 2));
            } else if (status == 'Out for delivery') {
                pickup = runDate.addDays(-transitDays);
                estimate = runDate;
            } else if (status == 'Delivered') {
                pickup = runDate.addDays(-6 - Math.mod(i * 5, 30));
                estimate = pickup.addDays(transitDays);
            } else {
                pickup = runDate.addDays(-2 - Math.mod(i, 4));
                estimate = pickup.addDays(transitDays);
            }

            rows.add(new Shipment__c(
                Account__c = customer.Id,
                Customer_Reference__c = Math.mod(i, 7) == 6 ? null : referencePrefix.get(customerName) + (4500 + c * 1000 + i),
                Service_Type__c = service,
                Pickup_Address__c = pickupByCustomer.get(customerName),
                Pickup_Postal_Code__c = pickupPostalByCustomer.get(customerName),
                Pickup_Date__c = pickup,
                Origin_City__c = originByCustomer.get(customerName),
                Destination_City__c = point[0] + ', ' + point[1],
                Recipient_Name__c = first + ' ' + last,
                Recipient_Address__c = point[3] + ', ' + point[0] + ', ' + point[1] + ', C.P. ' + point[2],
                Destination_Postal_Code__c = point[2],
                Recipient_Phone__c = '55-0000-' + (3000 + c * 1000 + i),
                Recipient_Email__c = (ascii(first) + '.' + ascii(last) + (c * 100 + i)).toLowerCase() + '@example.com',
                Delivery_Instructions__c = instructions[Math.mod(i, instructions.size())],
                Package_Description__c = packagesByCustomer.get(customerName)[Math.mod(i, 6)],
                Weight_Kg__c = kg,
                Declared_Value__c = declared,
                Price__c = amount,
                Carrier_Cost__c = (amount * (0.55 + Math.mod(i, 5) * 0.05)).setScale(2, RoundingMode.HALF_UP),
                Estimated_Delivery__c = estimate,
                Reschedule_Count__c = 0,
                Internal_Notes__c = (status == 'Exception'
                    ? 'Ops: recipient absent on the first attempt; EntregaYa holds the package at its ' + point[0] + ' station. '
                    : 'Ops: ' + service + ' service, pickup at the customer warehouse. ')
                    + (c == 0 ? 'Customer credit risk Low.' : 'Customer credit risk High: confirm payment terms before new pickups.')
            ));
            finalStatuses.add(status);
        }
    }

    Map<Id, String> codes = DeliveryAccessCode.insertWithCodes(rows);

    // ─── 5. Tracking numbers and codes must be exactly as designed ─────────
    Map<Id, Shipment__c> inserted = new Map<Id, Shipment__c>(
        [SELECT Id, Name FROM Shipment__c WHERE Id IN :rows WITH USER_MODE]);
    List<String> problems = new List<String>();
    for (Integer r = 0; r < rows.size(); r++) {
        String expected = trackingNumber(FIRST_NUMBER + r);
        String actual = inserted.get(rows[r].Id).Name;
        if (actual != expected) {
            problems.add('row ' + (r + 1) + ' got ' + actual + ', expected ' + expected);
            break;
        }
    }
    if (codes.size() != rows.size()) {
        problems.add(codes.size() + ' access codes returned for ' + rows.size() + ' shipments');
    }
    if (!problems.isEmpty()) {
        Database.rollback(beforeSeed);
        throw new SeedException('rolled back the whole load (accounts, contacts and shipments): '
            + String.join(problems, '; ') + '. The Auto Number counter is not at ' + trackingNumber(FIRST_NUMBER)
            + ', or the access code hashes were not stored. Load the seed in a new scratch org.');
    }

    // ─── 6. Final statuses (the trigger starts every shipment in Requested) ─
    List<Integer> deliveredByCustomer = new List<Integer>{ 0, 0 };
    for (Integer r = 0; r < rows.size(); r++) {
        Integer c = r / PER_CUSTOMER;
        Integer i = Math.mod(r, PER_CUSTOMER);
        String status = finalStatuses[r];
        Shipment__c row = rows[r];
        Shipment__c change = new Shipment__c(Id = row.Id, Status__c = status);
        if (status == 'Requested') {
            change.Last_Update__c = runAt.addHours(-1 - Math.mod(i, 20));
        } else if (status == 'Picked up') {
            change.Last_Update__c = runAt.addHours(-2 - Math.mod(i, 5));
            change.Last_Location__c = row.Origin_City__c;
        } else if (status == 'In transit') {
            change.Last_Update__c = runAt.addHours(-3 - Math.mod(i, 9));
            change.Last_Location__c = hubs[Math.mod(i, hubs.size())];
        } else if (status == 'Out for delivery') {
            change.Last_Update__c = runAt.addMinutes(-30 - Math.mod(i, 4) * 15);
            change.Last_Location__c = row.Destination_City__c;
        } else if (status == 'Delivered') {
            deliveredByCustomer[c]++;
            Datetime deliveredAt = mexicoCity(row.Estimated_Delivery__c, 10 + Math.mod(i, 8), Math.mod(i * 13, 60));
            change.Delivered_At__c = deliveredAt;
            change.Last_Update__c = deliveredAt;
            change.Last_Location__c = row.Destination_City__c;
            change.Proof_Id__c = 'PRF-8' + String.valueOf((c + 1) * 1000 + deliveredByCustomer[c]);
        } else {
            change.Last_Update__c = runAt.addHours(-3 - Math.mod(i, 6));
            change.Last_Location__c = row.Destination_City__c;
        }
        rows[r] = change;
    }
    Database.update(rows, true, AccessLevel.USER_MODE);

    // ─── 7. Report, then each clear access code once ───────────────────────
    System.debug(LoggingLevel.INFO, 'SEED|loaded|2 accounts, 2 contacts, ' + rows.size() + ' shipments ('
        + trackingNumber(FIRST_NUMBER) + '-' + trackingNumber(FIRST_NUMBER + rows.size() - 1) + ', '
        + (deliveredByCustomer[0] + deliveredByCustomer[1]) + ' Delivered)|dates relative to ' + String.valueOf(runDate) + ' America/Mexico_City');
    for (Integer r = 0; r < rows.size(); r++) {
        System.debug(LoggingLevel.INFO, 'SEEDCODE|' + trackingNumber(FIRST_NUMBER + r) + '|' + codes.remove(rows[r].Id));
    }
}
