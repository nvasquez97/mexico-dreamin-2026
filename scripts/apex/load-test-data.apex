// RutaCargo — test data (step 1 of 2): 2 customers with their contact and 120 shipments.
//   sf apex run -o <alias> -f scripts/apex/load-test-data.apex
// Then run scripts/apex/create-test-users.apex (users are setup objects: separate transaction).
// All names, addresses and phone numbers are fictional (".example" email domains).
// Idempotent: does nothing if the test customers already have shipments.
//
// Tracking numbers are an auto number (BR-05). To get exactly RC000001001..RC000001120 the script
// aligns the sequence first: it inserts and rolls back throw-away rows until the next number is 1001
// (only possible on an org whose sequence is still below 1001, e.g. a fresh dev/scratch org).

final Integer FIRST_NUMBER = 1001;
Date today = RutaCargoDates.today();
Datetime now = RutaCargoDates.now();

List<Account> existing = [
  SELECT Id
  FROM Account
  WHERE Name IN ('Abarrotes Acme', 'Globex Farma')
];
if (
  !existing.isEmpty() &&
  [SELECT COUNT() FROM Shipment__c WHERE Account__c IN :existing] > 0
) {
  System.debug('Test data already loaded. Nothing to do.');
  return;
}

// ---------------------------------------------------------------- align the auto number
Savepoint probePoint = Database.setSavepoint();
Shipment__c probe = new Shipment__c();
insert probe;
Integer nextNumber =
  Integer.valueOf(
    [SELECT Name FROM Shipment__c WHERE Id = :probe.Id].Name.substring(2)
  ) + 1;
Database.rollback(probePoint);
if (nextNumber > FIRST_NUMBER) {
  throw new IllegalArgumentException(
    'The tracking number sequence is already at ' +
      nextNumber +
      '; test numbers RC000001001.. cannot be reproduced in this org.'
  );
}
if (nextNumber < FIRST_NUMBER) {
  List<Shipment__c> burn = new List<Shipment__c>();
  for (Integer i = nextNumber; i < FIRST_NUMBER; i++) {
    burn.add(new Shipment__c());
  }
  Savepoint burnPoint = Database.setSavepoint();
  insert burn;
  Database.rollback(burnPoint);
}

// ---------------------------------------------------------------- customers
Id ownerId = UserInfo.getUserId();
Account acme = new Account(
  Name = 'Abarrotes Acme',
  Customer_Type__c = 'Business',
  Credit_Risk__c = 'Low',
  Credit_Limit__c = 500000,
  Phone = '55 5100 2001',
  BillingCity = 'Ciudad de México',
  OwnerId = ownerId
);
Account globex = new Account(
  Name = 'Globex Farma',
  Customer_Type__c = 'Business',
  Credit_Risk__c = 'High',
  Credit_Limit__c = 150000,
  Phone = '33 5200 3002',
  BillingCity = 'Guadalajara',
  OwnerId = ownerId
);
insert new List<Account>{ acme, globex };
insert new List<Contact>{
  new Contact(
    FirstName = 'Ana',
    LastName = 'López',
    Email = 'ana.lopez@abarrotes-acme.example',
    Phone = '55 5100 2001',
    AccountId = acme.Id,
    OwnerId = ownerId
  ),
  new Contact(
    FirstName = 'Marta',
    LastName = 'Ruiz',
    Email = 'marta.ruiz@globex-farma.example',
    Phone = '33 5200 3002',
    AccountId = globex.Id,
    OwnerId = ownerId
  )
};

// ---------------------------------------------------------------- reference data
// city | state | postal codes (comma separated) | phone area code
List<String> cities = new List<String>{
  'Ciudad de México|CDMX|06600,03100,11560,04510|55',
  'Guadalajara|Jal.|44100,44600,45040|33',
  'Monterrey|N.L.|64000,64620,66220|81',
  'Puebla|Pue.|72000,72530|222',
  'Querétaro|Qro.|76000,76090|442',
  'Mérida|Yuc.|97000,97130|999',
  'Tijuana|B.C.|22000,22420|664',
  'León|Gto.|37000,37160|477',
  'Toluca|Edo. Méx.|50000,50120|722',
  'Cancún|Q. Roo|77500,77533|998',
  'Oaxaca|Oax.|68000,68050|951',
  'San Luis Potosí|S.L.P.|78000,78216|444'
};
List<String> firstNames = new List<String>{
  'Lucía',
  'Mateo',
  'Sofía',
  'Diego',
  'Valeria',
  'Santiago',
  'Camila',
  'Emiliano',
  'Regina',
  'Leonardo',
  'Ximena',
  'Andrés',
  'Fernanda',
  'Rodrigo',
  'Daniela',
  'Iván',
  'Paola',
  'Héctor',
  'Renata',
  'Óscar'
};
List<String> lastNames = new List<String>{
  'Hernández',
  'García',
  'Martínez',
  'Ramírez',
  'Flores',
  'Torres',
  'Vázquez',
  'Morales',
  'Castillo',
  'Ortega',
  'Mendoza',
  'Aguilar',
  'Rojas',
  'Navarro',
  'Salazar',
  'Cervantes',
  'Domínguez',
  'Ibarra',
  'Pineda',
  'Zamora'
};
List<String> streets = new List<String>{
  'Av. Insurgentes Sur',
  'Calle Hidalgo',
  'Av. Juárez',
  'Calle Morelos',
  'Av. Reforma',
  'Calle Allende',
  'Calle 5 de Mayo',
  'Av. Revolución',
  'Calle Zaragoza',
  'Av. Universidad',
  'Calle Independencia',
  'Av. Constitución'
};
List<String> colonias = new List<String>{
  'Centro',
  'Del Valle',
  'Roma Norte',
  'Americana',
  'Obispado',
  'La Paz',
  'Jardines',
  'Las Águilas',
  'San Benito',
  'Reforma'
};
Map<Id, List<String>> contents = new Map<Id, List<String>>{
  acme.Id => new List<String>{
    'Abarrotes surtidos',
    'Café de grano 5 kg',
    'Especias y condimentos',
    'Latas de conserva',
    'Dulces típicos',
    'Aceite de oliva'
  },
  globex.Id => new List<String>{
    'Material de curación',
    'Suplementos vitamínicos',
    'Termómetros digitales',
    'Guantes de nitrilo',
    'Cubrebocas',
    'Básculas de farmacia'
  }
};
Map<Id, String> refPrefix = new Map<Id, String>{
  acme.Id => 'ACME-PO-2026-',
  globex.Id => 'GF-ORD-'
};
Map<Id, Integer> originIndex = new Map<Id, Integer>{
  acme.Id => 0,
  globex.Id => 1
};
Map<Id, String> pickupAddress = new Map<Id, String>{
  acme.Id => 'Calle Fresno 214, Col. Santa María la Ribera, Cuauhtémoc',
  globex.Id => 'Av. Mariano Otero 3150, Col. Jardines del Sol, Zapopan'
};
Map<Id, String> pickupPostal = new Map<Id, String>{
  acme.Id => '06400',
  globex.Id => '45050'
};

// 60 per customer: 8 Requested, 9 Picked up, 12 In transit, 8 Out for delivery, 15 Delivered, 8 Exception
List<String> plan = new List<String>();
Map<String, Integer> mix = new Map<String, Integer>{
  'Requested' => 8,
  'Picked up' => 9,
  'In transit' => 12,
  'Out for delivery' => 8,
  'Delivered' => 15,
  'Exception' => 8
};
for (String status : ShipmentConstants.STATUSES) {
  for (Integer i = 0; i < mix.get(status); i++) {
    plan.add(status);
  }
}

List<Shipment__c> shipments = new List<Shipment__c>();
Integer seq = 0;
for (Account customer : new List<Account>{ acme, globex }) {
  for (Integer i = 0; i < plan.size(); i++) {
    // interleave statuses so the list is realistic, not grouped
    String status = plan[Math.mod(i * 7, plan.size())];
    seq++;
    List<String> origin = cities[originIndex.get(customer.Id)].split('\\|');
    Integer destIdx = Math.mod(seq * 5 + 2, cities.size());
    if (destIdx == originIndex.get(customer.Id)) {
      destIdx = Math.mod(destIdx + 3, cities.size());
    }
    List<String> dest = cities[destIdx].split('\\|');
    List<String> postalCodes = dest[2].split(',');
    String service = Math.mod(seq, 3) == 0 ? 'Express' : 'Standard';
    Decimal weight = (Decimal.valueOf(Math.mod(seq * 37, 2900) + 50) / 100)
      .setScale(2); // 0.50 .. 29.49
    Decimal declared = Decimal.valueOf(Math.mod(seq * 1373, 48000) + 500); // 500 .. 48,499
    Decimal price = ShipmentPricing.calculate(service, weight, declared);
    Integer transit = ShipmentConstants.transitBusinessDays(service);

    // Dates relative to today (Mexico City) so every status makes sense
    Date pickup;
    if (status == 'Requested') {
      pickup = today.addDays(1 + Math.mod(i, 10));
    } else if (status == 'Picked up') {
      pickup = today.addDays(-Math.mod(i, 2));
    } else if (status == 'In transit') {
      pickup = today.addDays(-1 - Math.mod(i, 2));
    } else if (status == 'Out for delivery') {
      pickup = today.addDays(-(transit + 2));
    } else if (status == 'Delivered') {
      pickup = today.addDays(-(10 + Math.mod(i, 40)));
    } else {
      pickup = today.addDays(-(4 + Math.mod(i, 6)));
    }
    while (!RutaCargoDates.isBusinessDay(pickup)) {
      pickup = status == 'Requested' ? pickup.addDays(1) : pickup.addDays(-1);
    }
    Date estimated = RutaCargoDates.addBusinessDays(pickup, transit);
    if (status == 'Out for delivery') {
      estimated = today;
    }

    Integer nameSeed = seq + (customer.Id == globex.Id ? 7 : 0); // different recipients per customer
    String firstName = firstNames[Math.mod(nameSeed * 3, firstNames.size())];
    String lastName =
      lastNames[Math.mod(nameSeed * 7, lastNames.size())] +
      ' ' +
      lastNames[Math.mod(nameSeed * 11 + 4, lastNames.size())];
    String phone =
      dest[3] +
      ' 5' +
      String.valueOf(Math.mod(seq * 7919, 1000)).leftPad(3, '0') +
      ' ' +
      String.valueOf(Math.mod(seq * 104729, 10000)).leftPad(4, '0');

    Shipment__c s = new Shipment__c(
      Account__c = customer.Id,
      Status__c = status,
      Service_Type__c = service,
      Customer_Reference__c = Math.mod(seq, 6) == 0
        ? null
        : refPrefix.get(customer.Id) + String.valueOf(seq).leftPad(4, '0'),
      Pickup_Address__c = pickupAddress.get(customer.Id),
      Origin_City__c = origin[0] + ', ' + origin[1],
      Pickup_Postal_Code__c = pickupPostal.get(customer.Id),
      Pickup_Date__c = pickup,
      Destination_City__c = dest[0] + ', ' + dest[1],
      Destination_Postal_Code__c = postalCodes[
        Math.mod(seq, postalCodes.size())
      ],
      Recipient_Name__c = firstName + ' ' + lastName,
      Recipient_Address__c = streets[Math.mod(seq, streets.size())] +
        ' ' +
        (100 + Math.mod(seq * 53, 900)) +
        ', Col. ' +
        colonias[Math.mod(seq * 3, colonias.size())],
      Recipient_Phone__c = phone,
      Recipient_Email__c = firstName.toLowerCase().replaceAll('[^a-z]', '') +
        '.' +
        String.valueOf(seq) +
        '@correo.example',
      Delivery_Instructions__c = Math.mod(seq, 4) == 0
        ? 'Entregar en recepción, horario de 9 a 18 h.'
        : (Math.mod(seq, 4) == 1
            ? 'Tocar el timbre del departamento 3B.'
            : null),
      Package_Description__c = contents.get(customer.Id)[Math.mod(seq, 6)],
      Weight_Kg__c = weight,
      Declared_Value__c = declared,
      Price__c = price,
      Carrier_Cost__c = (price *
        (0.55 + Decimal.valueOf(Math.mod(seq, 20)) / 100))
        .setScale(2),
      Internal_Notes__c = Math.mod(seq, 5) == 0
        ? 'Cliente pidió confirmar recolección por teléfono.'
        : 'Sin incidencias.',
      Estimated_Delivery__c = estimated,
      Reschedule_Count__c = 0
    );
    // Tracking history
    if (status == 'Requested') {
      s.Last_Update__c = now.addHours(-(2 + i));
    } else if (status == 'Picked up') {
      s.Last_Location__c = origin[0] + ', ' + origin[1];
      s.Last_Update__c = now.addHours(-(3 + i));
    } else if (status == 'In transit') {
      List<String> hub = cities[Math.mod(destIdx + 1, cities.size())]
        .split('\\|');
      s.Last_Location__c = 'Centro de distribución ' + hub[0] + ', ' + hub[1];
      s.Last_Update__c = now.addHours(-(1 + i));
      if (Math.mod(i, 6) == 0) {
        // already rescheduled twice: shows the AC-003.4 limit
        s.Reschedule_Count__c = 2;
        s.Original_Estimated_Delivery__c = estimated;
        s.Estimated_Delivery__c = estimated.addDays(2);
      }
    } else if (status == 'Out for delivery') {
      s.Last_Location__c = dest[0] + ', ' + dest[1];
      s.Last_Update__c = now.addHours(-(1 + Math.mod(i, 5)));
    } else if (status == 'Delivered') {
      Datetime deliveredAt = Datetime.newInstanceGmt(
        estimated,
        Time.newInstance(17 + Math.mod(i, 6), 15, 0, 0)
      );
      s.Last_Location__c = dest[0] + ', ' + dest[1];
      s.Last_Update__c = deliveredAt;
      s.Delivered_At__c = deliveredAt;
      s.Proof_Id__c = 'PRF-' + String.valueOf(88000 + seq);
    } else {
      s.Last_Location__c = 'Centro de distribución ' + dest[0] + ', ' + dest[1];
      s.Last_Update__c = now.addHours(-(20 + i));
      s.Internal_Notes__c = 'Excepción: domicilio no localizado, se contactará al destinatario.';
    }
    shipments.add(s);
  }
}
insert shipments; // auto numbers follow list order: RC000001001 .. RC000001120

List<Shipment__c> check = [
  SELECT Name
  FROM Shipment__c
  WHERE Id IN :shipments
  ORDER BY Name
];
System.debug(
  'Loaded ' +
    check.size() +
    ' shipments: ' +
    check[0].Name +
    ' .. ' +
    check[check.size() - 1].Name
);
