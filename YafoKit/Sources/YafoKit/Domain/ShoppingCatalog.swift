import Foundation

/// Abteilungen in der Reihenfolge, in der man typischerweise durch den Supermarkt läuft.
nonisolated public enum ShoppingCategory: String, CaseIterable, Sendable {
    case produce, bakery, meat, dairy, pantry, breakfast, snacks, drinks, frozen, household, hygiene, baby, pets, other

    public var emoji: String {
        switch self {
        case .produce: "🥦"
        case .bakery: "🥖"
        case .meat: "🥩"
        case .dairy: "🧀"
        case .pantry: "🍝"
        case .breakfast: "🥣"
        case .snacks: "🍫"
        case .drinks: "🧃"
        case .frozen: "🧊"
        case .household: "🧽"
        case .hygiene: "🧴"
        case .baby: "🍼"
        case .pets: "🐾"
        case .other: "🛒"
        }
    }

    /// Position im Laden; kleiner = früher.
    public var aisle: Int { Self.allCases.firstIndex(of: self)! }
}

/// Bekannter Artikel mit Piktogramm, Abteilung und Namen (erster Name = Anzeigename).
nonisolated public struct ShoppingArticle: Sendable, Hashable {
    public let emoji: String
    public let category: ShoppingCategory
    public let germanNames: [String]
    public let englishNames: [String]

    /// Anzeigename in der Sprache des Geräts (Deutsch oder Englisch).
    public func name(languageCode: String? = Locale.current.language.languageCode?.identifier) -> String {
        languageCode == "de" ? germanNames[0] : englishNames[0]
    }
}

/// Mitgelieferter Artikelkatalog: liefert Piktogramm und Abteilung für eingetippte Namen.
/// Deutsche Komposita werden über ihr Grundwort erkannt („Vollkornbrot“ → Brot).
nonisolated public enum ShoppingCatalog {
    public static func article(for name: String) -> ShoppingArticle? {
        let key = normalize(name)
        guard !key.isEmpty else { return nil }
        if let exact = index[key] { return exact }
        // Längstes bekanntes Grundwort am Ende („Vollmilch“) oder ein ganzes Wort („Milk 1.5%“).
        let words = Set(key.split(whereSeparator: { !$0.isLetter }).map(String.init))
        return index.filter { name, _ in
            name.count >= 3 && (key.hasSuffix(name) || words.contains(name))
        }
        .max { $0.key.count < $1.key.count }?.value
    }

    public static func category(for name: String) -> ShoppingCategory {
        article(for: name)?.category ?? .other
    }

    public static func emoji(for name: String) -> String {
        article(for: name)?.emoji ?? ShoppingCategory.other.emoji
    }

    /// Katalogartikel, deren Name mit `prefix` beginnt, in der Sprache des Geräts.
    public static func suggestions(for prefix: String, languageCode: String? = Locale.current.language.languageCode?.identifier,
                                   limit: Int = 8) -> [String] {
        let key = normalize(prefix)
        guard !key.isEmpty else { return [] }
        let names = articles.compactMap { article -> String? in
            let all = article.germanNames + article.englishNames
            return all.contains { normalize($0).hasPrefix(key) } ? article.name(languageCode: languageCode) : nil
        }
        return Array(names.sorted { $0.count < $1.count }.prefix(limit))
    }

    static func normalize(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let index: [String: ShoppingArticle] = {
        var index: [String: ShoppingArticle] = [:]
        for article in articles {
            for name in article.germanNames + article.englishNames where index[normalize(name)] == nil {
                index[normalize(name)] = article
            }
        }
        return index
    }()

    private static func a(_ emoji: String, _ category: ShoppingCategory, _ german: String, _ english: String) -> ShoppingArticle {
        ShoppingArticle(emoji: emoji, category: category,
                        germanNames: german.components(separatedBy: "|"),
                        englishNames: english.components(separatedBy: "|"))
    }

    public static let articles: [ShoppingArticle] = [
        // Obst & Gemüse
        a("🍎", .produce, "Äpfel|Apfel", "Apples|Apple"),
        a("🍌", .produce, "Bananen|Banane", "Bananas|Banana"),
        a("🍐", .produce, "Birnen|Birne", "Pears|Pear"),
        a("🍊", .produce, "Orangen|Orange|Mandarinen|Clementinen", "Oranges|Orange|Mandarins|Clementines"),
        a("🍋", .produce, "Zitronen|Zitrone|Limetten", "Lemons|Lemon|Limes"),
        a("🍇", .produce, "Trauben|Weintrauben", "Grapes"),
        a("🍓", .produce, "Erdbeeren", "Strawberries"),
        a("🫐", .produce, "Heidelbeeren|Blaubeeren|Beeren|Himbeeren", "Blueberries|Berries|Raspberries"),
        a("🍉", .produce, "Melone|Wassermelone", "Melon|Watermelon"),
        a("🍍", .produce, "Ananas", "Pineapple"),
        a("🥝", .produce, "Kiwis|Kiwi", "Kiwis|Kiwi"),
        a("🥭", .produce, "Mango", "Mango"),
        a("🥑", .produce, "Avocados|Avocado", "Avocados|Avocado"),
        a("🍅", .produce, "Tomaten|Tomate", "Tomatoes|Tomato"),
        a("🥒", .produce, "Gurke|Gurken|Zucchini", "Cucumber|Cucumbers|Zucchini"),
        a("🫑", .produce, "Paprika", "Bell peppers|Peppers"),
        a("🥕", .produce, "Karotten|Möhren|Karotte", "Carrots|Carrot"),
        a("🥔", .produce, "Kartoffeln|Kartoffel", "Potatoes|Potato"),
        a("🧅", .produce, "Zwiebeln|Zwiebel", "Onions|Onion"),
        a("🧄", .produce, "Knoblauch", "Garlic"),
        a("🥦", .produce, "Brokkoli|Blumenkohl", "Broccoli|Cauliflower"),
        a("🥬", .produce, "Salat|Kopfsalat|Spinat|Eisbergsalat", "Lettuce|Salad|Spinach"),
        a("🌽", .produce, "Mais", "Corn"),
        a("🍄", .produce, "Pilze|Champignons", "Mushrooms"),
        a("🌿", .produce, "Kräuter|Petersilie|Basilikum|Schnittlauch", "Herbs|Parsley|Basil|Chives"),
        a("🫚", .produce, "Ingwer", "Ginger"),
        a("🍆", .produce, "Aubergine", "Eggplant|Aubergine"),
        a("🫛", .produce, "Erbsen|Bohnen", "Peas|Green beans"),

        // Brot & Backwaren
        a("🍞", .bakery, "Brot|Toast|Toastbrot", "Bread|Toast"),
        a("🥖", .bakery, "Baguette", "Baguette"),
        a("🥐", .bakery, "Brötchen|Croissants|Semmeln", "Rolls|Bread rolls|Croissants"),
        a("🥨", .bakery, "Brezeln|Breze|Laugenbrezel", "Pretzels"),
        a("🫓", .bakery, "Wraps|Tortillas|Fladenbrot", "Wraps|Tortillas|Flatbread"),
        a("🍰", .bakery, "Kuchen|Torte", "Cake"),

        // Fleisch, Wurst & Fisch
        a("🥩", .meat, "Fleisch|Rindfleisch|Steak|Hackfleisch|Hack", "Meat|Beef|Steak|Ground beef|Minced meat"),
        a("🍗", .meat, "Hähnchen|Hähnchenbrust|Hühnchen|Pute", "Chicken|Chicken breast|Turkey"),
        a("🥓", .meat, "Speck|Schinken|Bacon", "Bacon|Ham"),
        a("🌭", .meat, "Würstchen|Wiener|Bratwurst", "Sausages|Hot dogs"),
        a("🍖", .meat, "Wurst|Aufschnitt|Salami", "Cold cuts|Salami"),
        a("🐟", .meat, "Fisch|Lachs|Thunfisch", "Fish|Salmon|Tuna"),
        a("🦐", .meat, "Garnelen|Shrimps", "Shrimp|Prawns"),
        a("🌱", .meat, "Tofu", "Tofu"),

        // Kühlregal: Milch, Käse, Eier
        a("🥛", .dairy, "Milch|Hafermilch|Sojamilch", "Milk|Oat milk|Soy milk"),
        a("🧈", .dairy, "Butter|Margarine", "Butter|Margarine"),
        a("🧀", .dairy, "Käse|Gouda|Mozzarella|Parmesan|Frischkäse|Feta", "Cheese|Gouda|Mozzarella|Parmesan|Cream cheese|Feta"),
        a("🥚", .dairy, "Eier|Ei", "Eggs|Egg"),
        a("🍶", .dairy, "Joghurt|Quark|Skyr", "Yogurt|Yoghurt|Quark"),
        a("🥛", .dairy, "Sahne|Schmand|Saure Sahne", "Cream|Sour cream"),
        a("🍮", .dairy, "Pudding", "Pudding"),
        a("🥟", .dairy, "Tortellini|Gnocchi", "Tortellini|Gnocchi"),

        // Grundnahrungsmittel, Konserven, Gewürze
        a("🍝", .pantry, "Nudeln|Spaghetti|Pasta|Penne", "Pasta|Spaghetti|Noodles|Penne"),
        a("🍚", .pantry, "Reis", "Rice"),
        a("🌾", .pantry, "Mehl", "Flour"),
        a("🧂", .pantry, "Salz|Pfeffer|Gewürze", "Salt|Pepper|Spices"),
        a("🍬", .pantry, "Zucker", "Sugar"),
        a("🫒", .pantry, "Öl|Olivenöl|Sonnenblumenöl|Oliven", "Oil|Olive oil|Olives"),
        a("🍾", .pantry, "Essig", "Vinegar"),
        a("🥫", .pantry, "Dosentomaten|Passata|Tomatenmark|Konserven|Mais in der Dose", "Canned tomatoes|Passata|Tomato paste|Canned food"),
        a("🫘", .pantry, "Kidneybohnen|Linsen|Kichererbsen", "Kidney beans|Lentils|Chickpeas"),
        a("🍅", .pantry, "Ketchup", "Ketchup"),
        a("🟡", .pantry, "Senf|Mayonnaise|Mayo", "Mustard|Mayonnaise|Mayo"),
        a("🥣", .pantry, "Brühe|Suppe|Gemüsebrühe", "Broth|Stock|Soup"),
        a("🧁", .pantry, "Backpulver|Hefe|Vanillezucker", "Baking powder|Yeast|Vanilla sugar"),
        a("🫙", .pantry, "Soße|Pesto|Sojasoße", "Sauce|Pesto|Soy sauce"),

        // Frühstück
        a("🥣", .breakfast, "Müsli|Cornflakes|Haferflocken|Cerealien", "Muesli|Cereal|Cornflakes|Oats|Rolled oats"),
        a("🍓", .breakfast, "Marmelade|Konfitüre", "Jam"),
        a("🍯", .breakfast, "Honig", "Honey"),
        a("🍫", .breakfast, "Nutella|Schokocreme|Nougatcreme", "Nutella|Chocolate spread"),
        a("🥜", .breakfast, "Erdnussbutter", "Peanut butter"),
        a("☕️", .breakfast, "Kaffee|Kaffeebohnen|Kaffeepads|Kapseln", "Coffee|Coffee beans|Coffee pods"),
        a("🫖", .breakfast, "Tee", "Tea"),
        a("🍫", .breakfast, "Kakao|Kakaopulver", "Cocoa|Hot chocolate"),

        // Süßes & Snacks
        a("🍫", .snacks, "Schokolade", "Chocolate"),
        a("🍪", .snacks, "Kekse|Plätzchen", "Cookies|Biscuits"),
        a("🍬", .snacks, "Gummibärchen|Süßigkeiten|Bonbons", "Gummy bears|Candy|Sweets"),
        a("🥔", .snacks, "Chips", "Chips|Crisps"),
        a("🥨", .snacks, "Salzstangen|Knabberzeug", "Pretzel sticks|Snacks"),
        a("🥜", .snacks, "Nüsse|Erdnüsse|Mandeln", "Nuts|Peanuts|Almonds"),
        a("🍿", .snacks, "Popcorn", "Popcorn"),
        a("🍦", .snacks, "Eis|Eiscreme", "Ice cream"),

        // Getränke
        a("💧", .drinks, "Wasser|Mineralwasser|Sprudel", "Water|Mineral water|Sparkling water"),
        a("🧃", .drinks, "Saft|Apfelsaft|Orangensaft|Schorle", "Juice|Apple juice|Orange juice"),
        a("🥤", .drinks, "Cola|Limo|Limonade|Eistee", "Cola|Soda|Lemonade|Iced tea"),
        a("🍺", .drinks, "Bier", "Beer"),
        a("🍷", .drinks, "Wein|Rotwein|Weißwein", "Wine|Red wine|White wine"),
        a("🥂", .drinks, "Sekt|Prosecco|Champagner", "Sparkling wine|Prosecco|Champagne"),

        // Tiefkühl
        a("🍕", .frozen, "Pizza|Tiefkühlpizza", "Pizza|Frozen pizza"),
        a("🍟", .frozen, "Pommes", "Fries|French fries"),
        a("🥦", .frozen, "Tiefkühlgemüse|TK-Gemüse", "Frozen vegetables"),
        a("🐟", .frozen, "Fischstäbchen", "Fish fingers|Fish sticks"),
        a("🧊", .frozen, "Eiswürfel", "Ice cubes"),

        // Haushalt
        a("🧻", .household, "Toilettenpapier|Klopapier", "Toilet paper"),
        a("🧻", .household, "Küchenrolle|Küchenpapier", "Paper towels|Kitchen roll"),
        a("🧽", .household, "Schwämme|Spülschwamm", "Sponges"),
        a("🫧", .household, "Spülmittel|Spülmaschinentabs|Tabs", "Dish soap|Dishwasher tabs"),
        a("🧺", .household, "Waschmittel|Weichspüler", "Laundry detergent|Fabric softener"),
        a("🗑️", .household, "Müllbeutel|Mülltüten", "Trash bags|Bin bags"),
        a("🧼", .household, "Putzmittel|Reiniger|Allzweckreiniger", "Cleaner|Cleaning spray"),
        a("📦", .household, "Alufolie|Frischhaltefolie|Backpapier|Gefrierbeutel", "Aluminum foil|Cling film|Baking paper|Freezer bags"),
        a("🔋", .household, "Batterien", "Batteries"),
        a("💡", .household, "Glühbirne|Leuchtmittel", "Light bulb|Light bulbs"),
        a("🕯️", .household, "Kerzen|Teelichter", "Candles|Tea lights"),
        a("🌸", .household, "Blumen", "Flowers"),

        // Drogerie
        a("🪥", .hygiene, "Zahnpasta|Zahnbürste|Zahnseide", "Toothpaste|Toothbrush|Floss"),
        a("🧴", .hygiene, "Duschgel|Shampoo|Spülung|Bodylotion|Creme", "Shower gel|Shampoo|Conditioner|Body lotion|Lotion"),
        a("🧼", .hygiene, "Seife|Handseife", "Soap|Hand soap"),
        a("🪒", .hygiene, "Rasierer|Rasierklingen|Rasierschaum", "Razor|Razor blades|Shaving foam"),
        a("🧻", .hygiene, "Taschentücher", "Tissues"),
        a("🌸", .hygiene, "Deo|Deodorant", "Deodorant"),
        a("🩹", .hygiene, "Pflaster", "Band-aids|Plasters"),
        a("💊", .hygiene, "Medikamente|Schmerztabletten|Ibuprofen|Paracetamol", "Medicine|Painkillers|Ibuprofen|Paracetamol"),
        a("🌞", .hygiene, "Sonnencreme", "Sunscreen"),
        a("🩸", .hygiene, "Tampons|Binden", "Tampons|Pads"),
        a("🧽", .hygiene, "Wattepads|Wattestäbchen", "Cotton pads|Cotton buds"),

        // Baby
        a("👶", .baby, "Windeln", "Diapers|Nappies"),
        a("🧻", .baby, "Feuchttücher", "Wet wipes|Baby wipes"),
        a("🍼", .baby, "Babynahrung|Babybrei|Milchpulver", "Baby food|Formula"),

        // Tierbedarf
        a("🐱", .pets, "Katzenfutter|Katzenstreu", "Cat food|Cat litter"),
        a("🐶", .pets, "Hundefutter|Leckerlis", "Dog food|Dog treats"),
    ]
}
