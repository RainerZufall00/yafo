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

    /// Gezeichnete Grafik der Abteilung, für Überschriften und unbekannte Artikel.
    public var icon: String {
        switch self {
        case .produce: "apple"
        case .bakery: "bread"
        case .meat: "steak"
        case .dairy: "cheese"
        case .pantry: "can"
        case .breakfast: "coffee"
        case .snacks: "chocolate"
        case .drinks: "water"
        case .frozen: "frozen"
        case .household: "spray"
        case .hygiene: "shampoo"
        case .baby: "baby-bottle"
        case .pets: "paw"
        case .other: "basket"
        }
    }

    /// Position im Laden; kleiner = früher.
    public var aisle: Int { Self.allCases.firstIndex(of: self)! }
}

/// Bekannter Artikel mit Piktogramm, Abteilung und Namen (erster Name = Anzeigename).
/// `icon` benennt die gezeichnete Grafik (Asset `item-<icon>`), `emoji` dient als Ersatz.
nonisolated public struct ShoppingArticle: Sendable, Hashable {
    public let emoji: String
    public let icon: String
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

    public static func icon(for name: String) -> String {
        article(for: name)?.icon ?? ShoppingCategory.other.icon
    }

    /// Alle Grafiken, die Katalog und Abteilungen brauchen.
    public static var allIcons: Set<String> {
        Set(articles.map(\.icon) + ShoppingCategory.allCases.map(\.icon))
    }

    /// Katalogartikel, deren Name mit `prefix` beginnt, in der Sprache des Geräts.
    public static func suggestions(for prefix: String, languageCode: String? = Locale.current.language.languageCode?.identifier,
                                   limit: Int = 8) -> [String] {
        let key = normalize(prefix)
        guard !key.isEmpty else { return [] }
        // Passende Namen selbst vorschlagen („Majo“ → Majoran, nicht der erste Name der Gruppe);
        // passt nur die andere Sprache, den Anzeigenamen.
        var names: [String] = []
        for article in articles {
            let own = languageCode == "de" ? article.germanNames : article.englishNames
            let other = languageCode == "de" ? article.englishNames : article.germanNames
            let matching = own.filter { normalize($0).hasPrefix(key) }
            if !matching.isEmpty {
                names += matching
            } else if other.contains(where: { normalize($0).hasPrefix(key) }) {
                names.append(article.name(languageCode: languageCode))
            }
        }
        var seen = Set<String>()
        let unique = names.filter { seen.insert(normalize($0)).inserted }
        return Array(unique.sorted { $0.count < $1.count }.prefix(limit))
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

    private static func a(_ emoji: String, _ icon: String, _ category: ShoppingCategory, _ german: String,
                          _ english: String) -> ShoppingArticle {
        ShoppingArticle(emoji: emoji, icon: icon, category: category,
                        germanNames: german.components(separatedBy: "|"),
                        englishNames: english.components(separatedBy: "|"))
    }

    public static let articles: [ShoppingArticle] = [
        // Obst & Gemüse
        a("🍎", "apple", .produce, "Äpfel|Apfel", "Apples|Apple"),
        a("🍌", "banana", .produce, "Bananen|Banane", "Bananas|Banana"),
        a("🍐", "pear", .produce, "Birnen|Birne", "Pears|Pear"),
        a("🍊", "orange", .produce, "Orangen|Orange|Mandarinen|Clementinen", "Oranges|Orange|Mandarins|Clementines"),
        a("🍋", "lemon", .produce, "Zitronen|Zitrone|Limetten", "Lemons|Lemon|Limes"),
        a("🍇", "grapes", .produce, "Trauben|Weintrauben", "Grapes"),
        a("🍓", "strawberry", .produce, "Erdbeeren", "Strawberries"),
        a("🫐", "berries", .produce, "Heidelbeeren|Blaubeeren|Beeren|Himbeeren", "Blueberries|Berries|Raspberries"),
        a("🍉", "watermelon", .produce, "Melone|Wassermelone", "Melon|Watermelon"),
        a("🍍", "pineapple", .produce, "Ananas", "Pineapple"),
        a("🥝", "kiwi", .produce, "Kiwis|Kiwi", "Kiwis|Kiwi"),
        a("🥭", "mango", .produce, "Mango", "Mango"),
        a("🥑", "avocado", .produce, "Avocados|Avocado", "Avocados|Avocado"),
        a("🍅", "tomato", .produce, "Tomaten|Tomate", "Tomatoes|Tomato"),
        a("🥒", "cucumber", .produce, "Gurke|Gurken|Zucchini", "Cucumber|Cucumbers|Zucchini"),
        a("🫑", "bell-pepper", .produce, "Paprika", "Bell peppers|Peppers"),
        a("🥕", "carrot", .produce, "Karotten|Möhren|Karotte", "Carrots|Carrot"),
        a("🥔", "potato", .produce, "Kartoffeln|Kartoffel", "Potatoes|Potato"),
        a("🧅", "onion", .produce, "Zwiebeln|Zwiebel", "Onions|Onion"),
        a("🧄", "garlic", .produce, "Knoblauch", "Garlic"),
        a("🥦", "broccoli", .produce, "Brokkoli|Blumenkohl", "Broccoli|Cauliflower"),
        a("🥬", "lettuce", .produce, "Salat|Kopfsalat|Spinat|Eisbergsalat", "Lettuce|Salad|Spinach"),
        a("🌽", "corn", .produce, "Mais", "Corn"),
        a("🍄", "mushroom", .produce, "Pilze|Champignons", "Mushrooms"),
        a("🌿", "herbs", .produce, "Kräuter|Petersilie|Basilikum|Schnittlauch", "Herbs|Parsley|Basil|Chives"),
        a("🫚", "ginger", .produce, "Ingwer", "Ginger"),
        a("🍆", "eggplant", .produce, "Aubergine", "Eggplant|Aubergine"),
        a("🫛", "peas", .produce, "Erbsen|Bohnen", "Peas|Green beans"),
        a("🍑", "peach", .produce, "Pfirsiche|Pfirsich|Nektarinen|Aprikosen", "Peaches|Peach|Nectarines|Apricots"),
        a("🍒", "cherries", .produce, "Kirschen", "Cherries"),
        a("🟣", "plum", .produce, "Pflaumen|Zwetschgen", "Plums"),
        a("🍈", "melon", .produce, "Honigmelone", "Honeydew melon"),
        a("🍊", "grapefruit", .produce, "Grapefruit", "Grapefruit"),
        a("🥥", "coconut", .produce, "Kokosnuss", "Coconut"),
        a("🌴", "fig", .produce, "Datteln|Feigen", "Dates|Figs"),
        a("🍅", "cherry-tomatoes", .produce, "Cocktailtomaten|Kirschtomaten|Rispentomaten", "Cherry tomatoes"),
        a("🧅", "spring-onion", .produce, "Frühlingszwiebeln|Lauchzwiebeln|Schalotten|Rote Zwiebeln", "Spring onions|Scallions|Shallots|Red onions"),
        a("🥬", "leek", .produce, "Lauch|Porree", "Leek|Leeks"),
        a("🥬", "leafy-greens", .produce, "Rucola|Feldsalat|Babyspinat|Chicorée|Radicchio|Pak Choi", "Arugula|Rocket|Lamb's lettuce|Baby spinach|Chicory|Radicchio|Bok choy"),
        a("🥬", "cabbage", .produce, "Kohl|Weißkohl|Rotkohl|Wirsing|Grünkohl|Rosenkohl", "Cabbage|Red cabbage|Savoy cabbage|Kale|Brussels sprouts"),
        a("🥬", "celery", .produce, "Kohlrabi|Sellerie|Staudensellerie|Knollensellerie|Fenchel", "Kohlrabi|Celery|Celeriac|Fennel"),
        a("🥕", "carrot", .produce, "Suppengemüse|Suppengrün", "Soup vegetables"),
        a("🔴", "radish", .produce, "Radieschen|Rote Bete", "Radishes|Beetroot|Beets"),
        a("🥦", "asparagus", .produce, "Spargel", "Asparagus"),
        a("🎃", "pumpkin", .produce, "Kürbis|Hokkaido|Butternut", "Pumpkin|Squash|Butternut squash"),
        a("🍠", "sweet-potato", .produce, "Süßkartoffeln|Süßkartoffel", "Sweet potatoes|Sweet potato"),
        a("🌶️", "chili", .produce, "Chili|Chilischoten|Peperoni|Jalapeños", "Chili|Chilies|Chili peppers|Jalapeños"),
        a("🌿", "herbs", .produce, "Dill|Koriander|Minze|Rosmarin|Thymian|Salbei|Kresse|Zitronengras", "Dill|Cilantro|Coriander|Mint|Rosemary|Thyme|Sage|Cress|Lemongrass"),
        a("🌱", "sprouts", .produce, "Sprossen", "Sprouts"),
        a("🍄", "mushroom", .produce, "Steinpilze|Shiitake|Kräuterseitlinge", "Porcini|Shiitake|Oyster mushrooms"),
        a("🍓", "currants", .produce, "Johannisbeeren|Stachelbeeren|Brombeeren", "Currants|Gooseberries|Blackberries"),
        a("🍋", "rhubarb", .produce, "Rhabarber", "Rhubarb"),

        // Brot & Backwaren
        a("🍞", "bread", .bakery, "Brot|Toast|Toastbrot", "Bread|Toast"),
        a("🥖", "baguette", .bakery, "Baguette", "Baguette"),
        a("🥐", "roll", .bakery, "Brötchen|Croissants|Semmeln", "Rolls|Bread rolls|Croissants"),
        a("🥨", "pretzel", .bakery, "Brezeln|Breze|Laugenbrezel", "Pretzels"),
        a("🫓", "flatbread", .bakery, "Wraps|Tortillas|Fladenbrot", "Wraps|Tortillas|Flatbread"),
        a("🍰", "cake", .bakery, "Kuchen|Torte", "Cake"),
        a("🍞", "bread-round", .bakery, "Vollkornbrot|Roggenbrot|Bauernbrot|Weißbrot|Dinkelbrot", "Whole grain bread|Rye bread|White bread"),
        a("🍔", "burger-bun", .bakery, "Burgerbrötchen|Hot-Dog-Brötchen|Buns", "Burger buns|Hot dog buns|Buns"),
        a("🥖", "baguette", .bakery, "Ciabatta|Focaccia|Kräuterbaguette|Knoblauchbrot", "Ciabatta|Focaccia|Garlic bread"),
        a("🫓", "crispbread", .bakery, "Knäckebrot|Zwieback|Pita|Naan", "Crispbread|Rusks|Pita|Naan"),
        a("🧁", "muffin", .bakery, "Muffins|Muffin|Berliner|Donuts", "Muffins|Muffin|Doughnuts|Donuts"),

        // Fleisch, Wurst & Fisch
        a("🥩", "steak", .meat, "Fleisch|Rindfleisch|Steak|Hackfleisch|Hack", "Meat|Beef|Steak|Ground beef|Minced meat"),
        a("🍗", "chicken-leg", .meat, "Hähnchen|Hähnchenbrust|Hühnchen|Pute", "Chicken|Chicken breast|Turkey"),
        a("🥓", "bacon", .meat, "Speck|Schinken|Bacon", "Bacon|Ham"),
        a("🌭", "sausage", .meat, "Würstchen|Wiener|Bratwurst", "Sausages|Hot dogs"),
        a("🍖", "salami", .meat, "Wurst|Aufschnitt|Salami", "Cold cuts|Salami"),
        a("🐟", "fish", .meat, "Fisch|Lachs|Thunfisch", "Fish|Salmon|Tuna"),
        a("🦐", "shrimp", .meat, "Garnelen|Shrimps", "Shrimp|Prawns"),
        a("🌱", "tofu", .meat, "Tofu", "Tofu"),
        a("🍔", "burger-patty", .meat, "Burgerpatties|Frikadellen|Buletten", "Burger patties|Meatballs"),
        a("🥩", "steak", .meat, "Schnitzel|Gulasch|Schweinefleisch|Kalbfleisch|Lammfleisch", "Schnitzel|Goulash|Pork|Veal|Lamb"),
        a("🍗", "chicken-leg", .meat, "Hähnchenschenkel|Chicken Wings|Hähnchenflügel|Putenbrust", "Chicken thighs|Chicken wings|Turkey breast"),
        a("🥓", "bacon", .meat, "Schinkenwürfel|Speckwürfel|Pancetta|Pastrami", "Diced ham|Bacon bits|Pancetta|Pastrami"),
        a("🌭", "sausage", .meat, "Bockwurst|Weißwurst|Chorizo", "Frankfurters|Chorizo"),
        a("🐟", "fish", .meat, "Forelle|Kabeljau|Seelachs|Makrele|Sardinen|Hering", "Trout|Cod|Pollock|Mackerel|Sardines|Herring"),
        a("🦪", "mussel", .meat, "Muscheln|Miesmuscheln", "Mussels|Clams"),
        a("🌱", "veggie", .meat, "Fleischersatz|Veggie-Burger|Sojageschnetzeltes|Seitan|Tempeh|Falafel", "Meat substitute|Veggie burger|Seitan|Tempeh|Falafel"),

        // Kühlregal: Milch, Käse, Eier
        a("🥛", "milk", .dairy, "Milch|Hafermilch|Sojamilch", "Milk|Oat milk|Soy milk"),
        a("🧈", "butter", .dairy, "Butter|Margarine", "Butter|Margarine"),
        a("🧀", "cheese", .dairy, "Käse|Gouda|Mozzarella|Parmesan|Frischkäse|Feta", "Cheese|Gouda|Mozzarella|Parmesan|Cream cheese|Feta"),
        a("🥚", "egg", .dairy, "Eier|Ei", "Eggs|Egg"),
        a("🍶", "yogurt", .dairy, "Joghurt|Quark|Skyr", "Yogurt|Yoghurt|Quark"),
        a("🥛", "cream", .dairy, "Sahne|Schmand|Saure Sahne", "Cream|Sour cream"),
        a("🍮", "pudding", .dairy, "Pudding", "Pudding"),
        a("🥟", "tortellini", .dairy, "Tortellini|Gnocchi", "Tortellini|Gnocchi"),
        a("🧀", "cheese", .dairy, "Emmentaler|Cheddar|Camembert|Brie|Bergkäse|Ziegenkäse|Schafskäse|Halloumi|Grillkäse|Reibekäse|Ricotta|Mascarpone|Gorgonzola", "Emmental|Cheddar|Camembert|Brie|Goat cheese|Sheep cheese|Halloumi|Grated cheese|Ricotta|Mascarpone|Gorgonzola"),
        a("🥛", "cream", .dairy, "Crème fraîche|Schlagsahne|Kochsahne|Sojasahne|Hafersahne|Buttermilch|Kefir", "Crème fraîche|Whipping cream|Cooking cream|Buttermilk|Kefir"),
        a("🍶", "yogurt", .dairy, "Griechischer Joghurt|Magerquark|Hüttenkäse", "Greek yogurt|Cottage cheese"),
        a("🥛", "milk", .dairy, "Kondensmilch|H-Milch|Kakaomilch|Schokomilch", "Condensed milk|UHT milk|Chocolate milk"),
        a("🫙", "dip", .dairy, "Hummus|Tzatziki|Aioli|Guacamole|Obatzda", "Hummus|Tzatziki|Aioli|Guacamole"),
        a("🥐", "dough", .dairy, "Blätterteig|Pizzateig|Hefeteig|Mürbeteig|Croissantteig", "Puff pastry|Pizza dough|Dough"),
        a("🍝", "tortellini", .dairy, "Spätzle|Maultaschen|Schupfnudeln|Frische Pasta", "Spaetzle|Fresh pasta"),
        a("🥚", "egg", .dairy, "Eiersalat", "Egg salad"),

        // Grundnahrungsmittel, Konserven, Gewürze
        a("🍝", "penne", .pantry, "Nudeln|Pasta|Penne|Rigatoni|Makkaroni", "Pasta|Noodles|Penne|Rigatoni|Macaroni"),
        a("🍝", "spaghetti", .pantry, "Spaghetti|Linguine|Spaghettini", "Spaghetti|Linguine|Spaghettini"),
        a("🍚", "rice", .pantry, "Reis", "Rice"),
        a("🌾", "flour", .pantry, "Mehl", "Flour"),
        a("🧂", "salt", .pantry, "Salz|Pfeffer|Gewürze", "Salt|Pepper|Spices"),
        a("🍬", "sugar", .pantry, "Zucker", "Sugar"),
        a("🫒", "oil", .pantry, "Öl|Olivenöl|Sonnenblumenöl|Oliven", "Oil|Olive oil|Olives"),
        a("🍾", "vinegar", .pantry, "Essig", "Vinegar"),
        a("🥫", "can", .pantry, "Dosentomaten|Passata|Tomatenmark|Konserven|Mais in der Dose", "Canned tomatoes|Passata|Tomato paste|Canned food"),
        a("🫘", "beans", .pantry, "Kidneybohnen|Linsen|Kichererbsen", "Kidney beans|Lentils|Chickpeas"),
        a("🍅", "ketchup", .pantry, "Ketchup", "Ketchup"),
        a("🟡", "mustard", .pantry, "Senf|Mayonnaise|Mayo", "Mustard|Mayonnaise|Mayo"),
        a("🥣", "soup", .pantry, "Brühe|Suppe|Gemüsebrühe", "Broth|Stock|Soup"),
        a("🧁", "baking", .pantry, "Backpulver|Hefe|Vanillezucker", "Baking powder|Yeast|Vanilla sugar"),
        a("🫙", "sauce", .pantry, "Soße|Pesto|Sojasoße", "Sauce|Pesto|Soy sauce"),
        a("🪵", "cinnamon", .pantry, "Zimt|Zimtstangen", "Cinnamon|Cinnamon sticks"),
        a("🌿", "oregano", .pantry, "Oregano|Majoran|Basilikum getrocknet|Italienische Kräuter|Kräuter der Provence|Lorbeerblätter|Lorbeer|Getrocknete Kräuter", "Oregano|Marjoram|Dried basil|Italian herbs|Herbes de Provence|Bay leaves|Dried herbs"),
        a("🌶️", "chili", .pantry, "Paprikapulver|Paprika edelsüß|Paprika rosenscharf|Chilipulver|Chiliflocken|Cayennepfeffer|Geräuchertes Paprikapulver", "Paprika powder|Smoked paprika|Chili powder|Chili flakes|Cayenne pepper"),
        a("🧂", "spice-jar", .pantry, "Curry|Currypulver|Kurkuma|Kreuzkümmel|Kümmel|Koriandersamen|Garam Masala|Kardamom|Muskat|Muskatnuss|Nelken|Gewürznelken|Ingwerpulver|Knoblauchpulver|Zwiebelpulver|Safran|Sternanis|Anis", "Curry powder|Turmeric|Cumin|Caraway|Coriander seeds|Garam masala|Cardamom|Nutmeg|Cloves|Ground ginger|Garlic powder|Onion powder|Saffron|Star anise|Anise"),
        a("🧂", "spice-jar", .pantry, "Meersalz|Pfefferkörner|Zitronenpfeffer|Gewürzmischung|Grillgewürz", "Sea salt|Peppercorns|Lemon pepper|Seasoning|BBQ rub"),
        a("🌼", "vanilla", .pantry, "Vanille|Vanilleschote|Vanilleextrakt|Bourbon-Vanille", "Vanilla|Vanilla pod|Vanilla extract"),
        a("🍬", "sugar", .pantry, "Puderzucker|Brauner Zucker|Rohrzucker|Gelierzucker|Süßstoff", "Powdered sugar|Icing sugar|Brown sugar|Cane sugar|Jam sugar|Sweetener"),
        a("🧁", "baking", .pantry, "Natron|Trockenhefe|Speisestärke|Gelatine|Agar-Agar|Lebensmittelfarbe|Streusel|Kuvertüre|Kuchenglasur|Backmischung", "Baking soda|Dry yeast|Cornstarch|Gelatin|Agar|Food coloring|Sprinkles|Couverture|Icing|Cake mix"),
        a("🌾", "flour", .pantry, "Weizenmehl|Dinkelmehl|Vollkornmehl|Paniermehl|Semmelbrösel|Grieß|Polenta", "Wheat flour|Spelt flour|Whole wheat flour|Breadcrumbs|Semolina|Polenta"),
        a("🍫", "chocolate", .pantry, "Backkakao|Schokotropfen|Blockschokolade", "Baking cocoa|Chocolate chips|Baking chocolate"),
        a("🥥", "coconut", .pantry, "Kokosraspeln|Kokosmilch|Kokosöl", "Desiccated coconut|Coconut milk|Coconut oil"),
        a("🥜", "nut", .pantry, "Haselnüsse gemahlen|Mandeln gemahlen|Pinienkerne|Sonnenblumenkerne|Kürbiskerne|Sesam|Leinsamen|Chiasamen|Walnüsse|Cashews|Pekannüsse", "Ground hazelnuts|Ground almonds|Pine nuts|Sunflower seeds|Pumpkin seeds|Sesame|Flaxseed|Chia seeds|Walnuts|Cashews|Pecans"),
        a("🍇", "grapes", .pantry, "Rosinen|Trockenobst|Cranberries getrocknet|Marzipan", "Raisins|Dried fruit|Dried cranberries|Marzipan"),
        a("🫒", "oil", .pantry, "Rapsöl|Sesamöl|Bratöl|Speiseöl|Pflanzenöl", "Canola oil|Rapeseed oil|Sesame oil|Cooking oil|Vegetable oil"),
        a("🍾", "vinegar", .pantry, "Balsamico|Apfelessig|Weißweinessig|Rotweinessig|Reisessig", "Balsamic vinegar|Apple cider vinegar|White wine vinegar|Red wine vinegar|Rice vinegar"),
        a("🌶️", "hot-sauce", .pantry, "Sriracha|Tabasco|Sambal Oelek|Harissa|Sweet-Chili-Soße|Chilisoße", "Sriracha|Tabasco|Sambal oelek|Harissa|Sweet chili sauce|Hot sauce"),
        a("🫙", "sauce", .pantry, "Currypaste|Misopaste|Tahini|Worcestersoße|Teriyaki|Grillsoße|Barbecuesoße|Salatdressing|Dressing|Nudelsoße|Tomatensoße|Fischsoße|Maggi", "Curry paste|Miso paste|Tahini|Worcestershire sauce|Teriyaki|BBQ sauce|Salad dressing|Dressing|Pasta sauce|Tomato sauce|Fish sauce"),
        a("🍯", "honey", .pantry, "Ahornsirup|Agavendicksaft|Sirup", "Maple syrup|Agave syrup|Syrup"),
        a("🍋", "lemon", .pantry, "Zitronensaft", "Lemon juice"),
        a("🥫", "can", .pantry, "Gehackte Tomaten|Stückige Tomaten|Passierte Tomaten|Getrocknete Tomaten|Dosensuppe|Ravioli in der Dose", "Chopped tomatoes|Crushed tomatoes|Sun-dried tomatoes|Canned soup|Canned ravioli"),
        a("🥒", "pickles", .pantry, "Gewürzgurken|Essiggurken|Saure Gurken|Kapern|Sauerkraut|Rotkohl im Glas|Kimchi", "Pickles|Gherkins|Capers|Sauerkraut|Kimchi"),
        a("🫘", "beans", .pantry, "Weiße Bohnen|Schwarze Bohnen|Rote Linsen|Baked Beans|Bohnen in der Dose", "White beans|Black beans|Red lentils|Baked beans|Canned beans"),
        a("🐟", "can", .pantry, "Thunfisch in der Dose|Sardinen in der Dose", "Canned tuna|Canned sardines"),
        a("🍍", "can", .pantry, "Ananas in der Dose|Mandarinen in der Dose|Pfirsiche in der Dose|Apfelmus|Kompott", "Canned pineapple|Canned mandarins|Canned peaches|Applesauce|Compote"),
        a("🍝", "fusilli", .pantry, "Fusilli|Farfalle|Tagliatelle|Bandnudeln|Lasagneplatten|Lasagne|Spätzle getrocknet", "Fusilli|Farfalle|Tagliatelle|Lasagna sheets|Lasagna"),
        a("🍜", "noodles", .pantry, "Reisnudeln|Glasnudeln|Mie-Nudeln|Eiernudeln|Ramen|Udon|Soba|Instantnudeln|Fünf-Minuten-Terrine", "Rice noodles|Glass noodles|Egg noodles|Ramen|Udon|Soba|Instant noodles|Cup noodles"),
        a("🍚", "rice", .pantry, "Basmatireis|Jasminreis|Risottoreis|Milchreis|Sushireis|Vollkornreis|Wildreis", "Basmati rice|Jasmine rice|Risotto rice|Rice pudding|Sushi rice|Brown rice|Wild rice"),
        a("🌾", "grain", .pantry, "Couscous|Bulgur|Quinoa|Hirse|Graupen", "Couscous|Bulgur|Quinoa|Millet|Pearl barley"),
        a("🍙", "onigiri", .pantry, "Reispapier|Noriblätter|Algen", "Rice paper|Nori|Seaweed"),
        a("🥔", "potato", .pantry, "Kartoffelpüree|Kartoffelpüreepulver|Knödel|Klöße|Kartoffelknödel|Semmelknödel", "Mashed potato mix|Potato dumplings|Bread dumplings"),
        a("🥣", "stock-cube", .pantry, "Brühwürfel|Hühnerbrühe|Rinderbrühe|Fond", "Stock cubes|Bouillon cubes|Chicken stock|Beef stock"),
        a("🌮", "taco", .pantry, "Tacos|Taco-Schalen|Nachos|Tortilla-Chips|Fajita-Gewürz", "Taco shells|Tacos|Nachos|Tortilla chips|Fajita seasoning"),

        // Frühstück
        a("🥣", "cereal", .breakfast, "Müsli|Cornflakes|Haferflocken|Cerealien", "Muesli|Cereal|Cornflakes|Oats|Rolled oats"),
        a("🍓", "jam", .breakfast, "Marmelade|Konfitüre", "Jam"),
        a("🍯", "honey", .breakfast, "Honig", "Honey"),
        a("🍫", "spread", .breakfast, "Nutella|Schokocreme|Nougatcreme", "Nutella|Chocolate spread"),
        a("🥜", "spread", .breakfast, "Erdnussbutter", "Peanut butter"),
        a("☕️", "coffee", .breakfast, "Kaffee|Kaffeebohnen|Kaffeepads|Kapseln", "Coffee|Coffee beans|Coffee pods"),
        a("🫖", "tea", .breakfast, "Tee", "Tea"),
        a("🍫", "cocoa", .breakfast, "Kakao|Kakaopulver", "Cocoa|Hot chocolate"),
        a("🥣", "cereal", .breakfast, "Porridge|Granola|Knuspermüsli|Schokomüsli|Overnight Oats", "Porridge|Granola|Crunchy muesli"),
        a("🍫", "spread", .breakfast, "Schokoaufstrich|Brotaufstrich|Aufstrich", "Spread"),
        a("🍋", "jam", .breakfast, "Lemon Curd", "Lemon curd"),
        a("☕️", "coffee", .breakfast, "Espresso|Kaffeepulver|Filterkaffee|Löslicher Kaffee|Instantkaffee|Kaffeefilter", "Espresso|Ground coffee|Instant coffee|Coffee filters"),
        a("🫖", "tea", .breakfast, "Früchtetee|Kräutertee|Grüner Tee|Schwarzer Tee|Pfefferminztee|Kamillentee", "Fruit tea|Herbal tea|Green tea|Black tea|Peppermint tea|Chamomile tea"),
        a("🥛", "milk", .breakfast, "Kaffeesahne|Kaffeeweißer|Barista-Milch", "Coffee creamer|Creamer"),

        // Süßes & Snacks
        a("🍫", "chocolate", .snacks, "Schokolade", "Chocolate"),
        a("🍪", "cookie", .snacks, "Kekse|Plätzchen", "Cookies|Biscuits"),
        a("🍬", "candy", .snacks, "Gummibärchen|Süßigkeiten|Bonbons", "Gummy bears|Candy|Sweets"),
        a("🥔", "chips", .snacks, "Chips", "Chips|Crisps"),
        a("🥨", "pretzel", .snacks, "Salzstangen|Knabberzeug", "Pretzel sticks|Snacks"),
        a("🥜", "nut", .snacks, "Nüsse|Erdnüsse|Mandeln", "Nuts|Peanuts|Almonds"),
        a("🍿", "popcorn", .snacks, "Popcorn", "Popcorn"),
        a("🍦", "ice-cream", .snacks, "Eis|Eiscreme", "Ice cream"),
        a("🍪", "cookie", .snacks, "Butterkekse|Löffelbiskuits|Waffeln|Lebkuchen|Spekulatius|Reiswaffeln|Maiswaffeln", "Butter biscuits|Ladyfingers|Wafers|Gingerbread|Speculoos|Rice cakes|Corn cakes"),
        a("🍬", "candy", .snacks, "Fruchtgummi|Lakritz|Kaugummi|Marshmallows|Hustenbonbons|Lutscher", "Fruit gums|Licorice|Chewing gum|Marshmallows|Cough drops|Lollipops"),
        a("🍫", "chocolate", .snacks, "Schokoriegel|Pralinen|Weiße Schokolade|Zartbitterschokolade", "Chocolate bars|Pralines|White chocolate|Dark chocolate"),
        a("🥣", "bar", .snacks, "Müsliriegel|Proteinriegel", "Granola bars|Cereal bars|Protein bars"),
        a("🥜", "nut", .snacks, "Erdnussflips|Studentenfutter|Cashewkerne|Pistazien", "Peanut puffs|Trail mix|Cashew nuts|Pistachios"),
        a("🥨", "cracker", .snacks, "Cracker|Kräcker|Käsecracker", "Crackers|Cheese crackers"),

        // Getränke
        a("💧", "water", .drinks, "Wasser|Mineralwasser|Sprudel", "Water|Mineral water|Sparkling water"),
        a("🧃", "juice", .drinks, "Saft|Apfelsaft|Orangensaft|Schorle", "Juice|Apple juice|Orange juice"),
        a("🥤", "soda", .drinks, "Cola|Limo|Limonade|Eistee", "Cola|Soda|Lemonade|Iced tea"),
        a("🍺", "beer", .drinks, "Bier", "Beer"),
        a("🍷", "wine", .drinks, "Wein|Rotwein|Weißwein", "Wine|Red wine|White wine"),
        a("🥂", "sparkling", .drinks, "Sekt|Prosecco|Champagner", "Sparkling wine|Prosecco|Champagne"),
        a("🥤", "soda", .drinks, "Fanta|Sprite|Spezi|Ginger Ale|Tonic Water|Bitter Lemon|Energydrink|Red Bull|Mate", "Fanta|Sprite|Ginger ale|Tonic water|Bitter lemon|Energy drink|Red Bull|Club-Mate"),
        a("🧃", "juice", .drinks, "Multivitaminsaft|Traubensaft|Tomatensaft|Smoothie|Nektar|Sirup für Getränke|Himbeersirup", "Multivitamin juice|Grape juice|Tomato juice|Smoothie|Nectar|Cordial"),
        a("🍺", "beer", .drinks, "Pils|Radler|Weizenbier|Alkoholfreies Bier|Cider|Apfelwein", "Lager|Shandy|Wheat beer|Alcohol-free beer|Cider"),
        a("🍸", "spirits", .drinks, "Gin|Wodka|Whisky|Likör|Aperol|Lillet|Schnaps|Spirituosen|Glühwein|Eierlikör", "Gin|Vodka|Whisky|Whiskey|Liqueur|Aperol|Lillet|Spirits|Mulled wine|Eggnog"),
        a("🥛", "milk", .drinks, "Hafer Drink|Haferdrink|Mandeldrink|Mandelmilch|Reisdrink|Sojadrink", "Oat drink|Almond milk|Almond drink|Rice milk|Soy drink"),

        // Tiefkühl
        a("🍕", "pizza", .frozen, "Pizza|Tiefkühlpizza", "Pizza|Frozen pizza"),
        a("🍟", "fries", .frozen, "Pommes", "Fries|French fries"),
        a("🥦", "frozen", .frozen, "Tiefkühlgemüse|TK-Gemüse", "Frozen vegetables"),
        a("🐟", "fish-fingers", .frozen, "Fischstäbchen", "Fish fingers|Fish sticks"),
        a("🧊", "ice-cubes", .frozen, "Eiswürfel", "Ice cubes"),
        a("🥬", "frozen", .frozen, "TK-Spinat|Rahmspinat|TK-Erbsen|TK-Kräuter|TK-Brokkoli|Edamame", "Frozen spinach|Creamed spinach|Frozen peas|Frozen herbs|Edamame"),
        a("🍓", "frozen", .frozen, "TK-Beeren|TK-Obst|Tiefkühlobst", "Frozen berries|Frozen fruit"),
        a("🍟", "fries", .frozen, "Kartoffelecken|Wedges|Kroketten|Rösti|Ofenkartoffeln", "Potato wedges|Croquettes|Hash browns"),
        a("🐟", "fish", .frozen, "Backfisch|Schlemmerfilet|Tiefkühlfisch", "Battered fish|Frozen fish"),
        a("🍗", "chicken-leg", .frozen, "Chicken Nuggets|Nuggets|Cordon bleu", "Chicken nuggets|Nuggets"),
        a("🥟", "dumpling", .frozen, "Dumplings|Gyoza|Frühlingsrollen|Baguettebrötchen zum Aufbacken|Aufbackbrötchen", "Dumplings|Gyoza|Spring rolls|Bake-off rolls"),
        a("🍧", "ice-pop", .frozen, "Wassereis|Sorbet|Eis am Stiel|Mochi", "Ice pops|Sorbet|Popsicles|Mochi"),
        a("🍕", "pizza", .frozen, "Flammkuchen|Lasagne TK|Fertiggericht", "Tarte flambée|Ready meal|Frozen meal"),

        // Haushalt
        a("🧻", "toilet-paper", .household, "Toilettenpapier|Klopapier", "Toilet paper"),
        a("🧻", "paper-towel", .household, "Küchenrolle|Küchenpapier", "Paper towels|Kitchen roll"),
        a("🧽", "sponge", .household, "Schwämme|Spülschwamm", "Sponges"),
        a("🫧", "dish-soap", .household, "Spülmittel|Spülmaschinentabs|Tabs", "Dish soap|Dishwasher tabs"),
        a("🧺", "detergent", .household, "Waschmittel|Weichspüler", "Laundry detergent|Fabric softener"),
        a("🗑️", "trash-bag", .household, "Müllbeutel|Mülltüten", "Trash bags|Bin bags"),
        a("🧼", "spray", .household, "Putzmittel|Reiniger|Allzweckreiniger", "Cleaner|Cleaning spray"),
        a("📦", "foil", .household, "Alufolie|Frischhaltefolie|Backpapier|Gefrierbeutel", "Aluminum foil|Cling film|Baking paper|Freezer bags"),
        a("🔋", "batteries", .household, "Batterien", "Batteries"),
        a("💡", "light-bulb", .household, "Glühbirne|Leuchtmittel", "Light bulb|Light bulbs"),
        a("🕯️", "candle", .household, "Kerzen|Teelichter", "Candles|Tea lights"),
        a("🌸", "flower", .household, "Blumen", "Flowers"),
        a("🧽", "cloth", .household, "Schwammtücher|Spültücher|Mikrofasertücher|Putzlappen|Wischtücher", "Sponge cloths|Dishcloths|Microfiber cloths|Cleaning cloths"),
        a("🫧", "dish-soap", .household, "Geschirrspülmittel|Spüli|Klarspüler|Spülmaschinensalz|Regeneriersalz|Maschinenpfleger", "Dishwashing liquid|Rinse aid|Dishwasher salt|Machine cleaner"),
        a("🧺", "detergent", .household, "Waschpulver|Colorwaschmittel|Feinwaschmittel|Fleckentferner|Hygienespüler|Waschmittelblätter", "Washing powder|Color detergent|Delicate detergent|Stain remover|Laundry sanitizer|Laundry sheets"),
        a("🧼", "spray", .household, "WC-Reiniger|Badreiniger|Glasreiniger|Entkalker|Schimmelentferner|Desinfektionsmittel|Desinfektionsspray|Scheuermilch|Bodenreiniger", "Toilet cleaner|Bathroom cleaner|Glass cleaner|Descaler|Mould remover|Disinfectant|Floor cleaner"),
        a("🗑️", "trash-bag", .household, "Biomüllbeutel|Gelbe Säcke|Staubsaugerbeutel", "Compost bags|Recycling bags|Vacuum bags"),
        a("🧻", "tissues", .household, "Servietten|Taschentuchbox", "Napkins|Tissue box"),
        a("📦", "foil", .household, "Butterbrotpapier|Muffinförmchen|Zahnstocher|Strohhalme|Pappteller|Pappbecher", "Sandwich paper|Muffin cases|Toothpicks|Straws|Paper plates|Paper cups"),
        a("🔥", "fire", .household, "Streichhölzer|Feuerzeug|Grillkohle|Anzünder", "Matches|Lighter|Charcoal|Fire starters"),
        a("🔋", "batteries", .household, "Knopfzellen|Akkus", "Button cells|Rechargeable batteries"),
        a("🩹", "tape", .household, "Klebeband|Tesafilm|Paketband", "Tape|Sticky tape|Packing tape"),
        a("🎁", "gift", .household, "Geschenkpapier|Geburtstagskarte|Glückwunschkarte|Karte", "Wrapping paper|Birthday card|Greeting card|Card"),
        a("🪴", "plant", .household, "Blumenerde|Dünger|Pflanzen", "Potting soil|Fertilizer|Plants"),

        // Drogerie
        a("🪥", "toothpaste", .hygiene, "Zahnpasta|Zahnbürste|Zahnseide", "Toothpaste|Toothbrush|Floss"),
        a("🧴", "shampoo", .hygiene, "Duschgel|Shampoo|Spülung|Bodylotion|Creme", "Shower gel|Shampoo|Conditioner|Body lotion|Lotion"),
        a("🧼", "soap", .hygiene, "Seife|Handseife", "Soap|Hand soap"),
        a("🪒", "razor", .hygiene, "Rasierer|Rasierklingen|Rasierschaum", "Razor|Razor blades|Shaving foam"),
        a("🧻", "tissues", .hygiene, "Taschentücher", "Tissues"),
        a("🌸", "deodorant", .hygiene, "Deo|Deodorant", "Deodorant"),
        a("🩹", "bandage", .hygiene, "Pflaster", "Band-aids|Plasters"),
        a("💊", "pills", .hygiene, "Medikamente|Schmerztabletten|Ibuprofen|Paracetamol", "Medicine|Painkillers|Ibuprofen|Paracetamol"),
        a("🌞", "sunscreen", .hygiene, "Sonnencreme", "Sunscreen"),
        a("🩸", "pad", .hygiene, "Tampons|Binden", "Tampons|Pads"),
        a("🧽", "cotton", .hygiene, "Wattepads|Wattestäbchen", "Cotton pads|Cotton buds"),
        a("🫧", "pump", .hygiene, "Flüssigseife|Waschgel|Gesichtsreinigung|Abschminktücher", "Liquid soap|Face wash|Cleanser|Makeup wipes"),
        a("🧴", "cream-jar", .hygiene, "Gesichtscreme|Feuchtigkeitscreme|Handcreme|Lippenpflege|Labello|Haarspülung|Haargel|Haarspray|Haarwachs", "Face cream|Moisturizer|Hand cream|Lip balm|Hair conditioner|Hair gel|Hairspray|Hair wax"),
        a("🪥", "toothpaste", .hygiene, "Mundspülung|Zahnbürstenköpfe|Interdentalbürsten|Zahnseide-Sticks", "Mouthwash|Toothbrush heads|Interdental brushes|Floss picks"),
        a("💄", "makeup", .hygiene, "Make-up|Mascara|Wimperntusche|Lippenstift|Concealer|Nagellack|Nagellackentferner|Nagelfeile", "Makeup|Mascara|Lipstick|Concealer|Nail polish|Nail polish remover|Nail file"),
        a("🎀", "comb", .hygiene, "Haargummis|Haarspangen|Haarbürste|Kamm", "Hair ties|Hair clips|Hairbrush|Comb"),
        a("🩸", "pad", .hygiene, "Slipeinlagen|Menstruationstasse", "Panty liners|Menstrual cup"),
        a("💊", "pills", .hygiene, "Aspirin|Nasenspray|Hustensaft|Hustensirup|Halstabletten|Vitamine|Vitamintabletten|Magnesium|Fieberthermometer|Schnelltest", "Aspirin|Nasal spray|Cough syrup|Throat lozenges|Vitamins|Magnesium|Thermometer|Rapid test"),
        a("🩹", "bandage", .hygiene, "Blasenpflaster|Verband|Mullbinden|Desinfektionsspray für Wunden|Wundsalbe", "Blister plasters|Bandage|Gauze|Wound spray|Wound ointment"),
        a("😷", "mask", .hygiene, "Masken|FFP2-Masken|Mundschutz", "Masks|Face masks|FFP2 masks"),
        a("🦟", "insect", .hygiene, "Mückenspray|Mückenschutz|Zeckenzange", "Insect repellent|Mosquito spray|Tick remover"),

        // Baby
        a("🧷", "diaper", .baby, "Windeln|Pampers|Schwimmwindeln|Pants", "Diapers|Nappies|Swim diapers"),
        a("🫧", "wipes", .baby, "Feuchttücher|Feuchte Tücher|Babytücher", "Wet wipes|Baby wipes"),
        a("🧴", "cream-jar", .baby, "Wundschutzcreme|Zinksalbe|Babyöl|Babyshampoo|Babycreme", "Diaper cream|Zinc cream|Baby oil|Baby shampoo|Baby lotion"),
        a("🍼", "baby-bottle", .baby, "Fläschchen|Sauger|Schnuller|Beruhigungssauger", "Baby bottles|Teats|Pacifier|Dummy"),
        a("🍐", "pouch", .baby, "Quetschies|Quetschbeutel|Gläschen|Breigläschen|Babykekse|Hirsebrei|Getreidebrei", "Fruit pouches|Pouches|Baby jars|Baby biscuits|Baby cereal"),
        a("🍼", "baby-food", .baby, "Babynahrung|Babybrei|Milchpulver", "Baby food|Formula"),

        // Tierbedarf
        a("🐱", "cat", .pets, "Katzenfutter|Katzenstreu", "Cat food|Cat litter"),
        a("🐶", "dog", .pets, "Hundefutter|Leckerlis", "Dog food|Dog treats"),
        a("🐾", "paw", .pets, "Katzenleckerlis|Kauknochen|Kotbeutel|Hundekotbeutel|Tierfutter", "Cat treats|Chews|Poop bags|Pet food"),
        a("🐦", "bird", .pets, "Vogelfutter|Meisenknödel", "Bird seed|Fat balls"),
        a("🐠", "fish", .pets, "Fischfutter", "Fish food"),
    ]
}
