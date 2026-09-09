// Soko Vibe Duka — static data: categories, regions/districts, labels.
// Regions + districts generated from lib/constants/tanzania_districts.dart
// (CC-BY-4.0 open-admin-data, 31 regions). Labels are sw default + en.

const SV_CATEGORIES = [
  'Phones & Tablets', 'Electronics', 'Fashion & Clothing', 'Home & Garden',
  'Vehicles & Spare Parts', 'Health & Beauty', 'Sports & Outdoors',
  'Toys & Games', 'Books & Stationery', 'Supermarket', 'Agriculture', 'Services',
];

const SV_REGIONS = ["Arusha","Dar es Salaam","Dodoma","Geita","Iringa","Kagera","Katavi","Kigoma","Kilimanjaro","Lindi","Manyara","Mara","Mbeya","Mjini Magharibi","Morogoro","Mtwara","Mwanza","Njombe","Pwani","Rukwa","Ruvuma","Shinyanga","Simiyu","Singida","Songwe","Tabora","Tanga","Kaskazini Pemba","Kusini Pemba","Kaskazini Unguja","Kusini Unguja"];

const SV_DISTRICTS = {"Rukwa":["Kalambo","Nkasi","Sumbawanga City","Sumbawanga"],"Songwe":["Ileje","Mbozi","Momba","Songwe","Tunduma"],"Kilimanjaro":["Hai","Moshi City","Moshi","Mwanga","Rombo","Same","Siha"],"Mtwara":["Masasi City","Masasi","Mtwara City","Mtwara","Nanyumbu","Newala City","Newala","Tandahimba"],"Kaskazini Unguja":["Kaskazini A","Kaskazini B"],"Kagera":["Biharamulo","Bukoba City","Bukoba","Karagwe","Kyerwa","Missenyi","Muleba","Ngara"],"Mjini Magharibi":["Magharibi","Mjini"],"Kaskazini Pemba":["Wete","Micheweni"],"Pwani":["Bagamoyo","Chalinze","Kibaha City","Kibaha","Kisarawe","Mafia","Mkuranga","Rufiji"],"Simiyu":["Bariadi","Busega","Itilima","Maswa","Meatu"],"Dar es Salaam":["Ilala","Kigamboni","Kinondoni","Temeke","Ubungo"],"Shinyanga":["Kahama City","Kahama","Kishapu","Msalala","Shinyanga City","Shinyanga","Ushetu"],"Manyara":["Babati City","Babati","Hanang","Kiteto","Mbulu","Simanjiro"],"Mara":["Bunda","Butiama","Musoma City","Musoma","Rorya","Serengeti","Tarime"],"Tanga":["Bumbuli","Handeni City","Handeni","Kilindi","Korogwe City","Korogwe","Lushoto","Mkinga","Muheza","Pangani","Tanga City"],"Morogoro":["Gairo","Ifakara","Kilombero","Kilosa","Malinyi","Morogoro City","Morogoro","Mvomero","Ulanga"],"Kusini Pemba":["Chake Chake","Mkoani"],"Dodoma":["Bahi","Chamwino","Chemba","Dodoma City","Kongwa","Kondoa","Mpwapwa"],"Singida":["Ikungi","Iramba","Itigi","Manyoni","Mkalama","Singida City","Singida"],"Ruvuma":["Mbinga","Namtumbo","Nyasa","Songea City","Songea","Tunduru"],"Kusini Unguja":["Kati","Kusini"],"Katavi":["Mlele","Mpanda","Mpimbwe","Tanganyika"],"Lindi":["Kilwa","Lindi City","Lindi","Liwale","Nachingwea","Ruangwa"],"Geita":["Bukombe","Chato","Geita","Mbogwe","Nyang'hwale"],"Tabora":["Igunga","Kaliua","Nzega","Sikonge","Tabora City","Urambo","Uyui"],"Arusha":["Arusha City","Arusha","Karatu","Longido","Meru","Monduli","Ngorongoro"],"Iringa":["Iringa City","Iringa","Kilolo","Mufindi"],"Kigoma":["Buhigwe","Kakonko","Kasulu City","Kasulu","Kibondo","Kigoma City","Kigoma","Uvinza"],"Mbeya":["Busokelo","Chunya","Kyela","Mbarali","Mbeya City","Mbeya","Rungwe"],"Mwanza":["Bukoba City","Buchosa","Kwimba","Magu","Misungwi","Nyamagana","Sengerema","Ukerewe"]};

const SV_T = {
  sw: {
    nav_home: 'Nyumbani', nav_categories: 'Kategoria', nav_orders: 'Agizo Zangu',
    nav_account: 'Akaunti', nav_signin: 'Ingia', search_ph: 'Tafuta bidhaa...',
    splash_p: 'Hujambo! Duka la Soko Vibe linapakia bidhaa zako.',
    home_hero_kicker: 'Soko la Tanzania', home_hero_title: 'Nunua na kuuza popote Tanzania.',
    home_hero_sub: 'Malipo salama kupitia ClickPesa na escrow — bidhaa unayoipata ndiyo unayolipia.',
    home_new: 'Bidhaa mpya', home_browse: 'Vinjari', featured: 'Zinazoangaziwa',
    categories: 'Kategoria', all: 'Zote', load_more: 'Pakia zaidi',
    empty: 'Hakuna bidhaa', empty_filter: 'Hakuna bidhaa zinazolingana',
    view_detail: 'Angalia', add_cart: 'Ongeza kwenye kikapu', buy_now: 'Nunua Sasa',
    in_stock: 'Zipo', out_stock: 'Zimeisha', qty: 'Idadi', add_to_cart_ok: 'Imeongezwa kwenye kikapu',
    cart_title: 'Kikapu', cart_empty: 'Kikapu chako kipo tupu.', cart_browse: 'Vinjari bidhaa',
    cart_seller: 'Muuzaji', remove: 'Ondoa', cart_total: 'Jumla', cart_checkout: 'Tengeneza oda',
    back: 'Rudi', seller: 'Muuzaji', condition: 'Hali', location: 'Mahali',
    description: 'Maelezo', attributes: 'Sifa nyingine', variants: 'Vitokezi',
    checkout_title: 'Malipo', checkout_addr: 'Anwani ya ununuzi',
    region: 'Mkoa', district: 'Wilaya', ward: 'Kata', street: 'Mtaa / barabara',
    landmarks: 'Alama za kipekee (si lazima)', phone: 'Namba ya simu (kwa USSD)',
    delivery: 'Namna ya kupokea', deliver_local: 'Ndani ya jiji / senioribu',
    fee_note: 'Ukomo wa mfumo (3.5%) + shipping unahesabiwa upande wa muuzaji',
    place_order: 'Tengeneza Oda na Ulipa', processing: 'Inachakata...',
    pay_wait: 'Tumekutumia USSD prompt kwenye simu yako. Lipa uone "Lipa" na weka PIN.',
    pay_status_pending: 'Inasubiri malipo...', pay_status_paid: 'Malipo yametambuliwa!',
    pay_done: 'Agizo limekamilishwa — escrow imeanzishwa.', pay_failed: 'Malipo hayajafika.',
    pay_new: 'Tuma USSD tena', order_created: 'Agizo limeanzishwa.',
    need_auth: 'Ingia kwanza ili kuendelea.', signin_title: 'Ingia',
    signup_title: 'Sajili akaunti', name: 'Jina kamili', email: 'Barua pepe',
    password: 'Nenosiri', have_account: 'Una akaunti?', no_account: 'Huna akaunti?',
    submit_signin: 'Ingia', submit_signup: 'Sajili', signout: 'Ondoka',
    profile: 'Akaunti yako', orders_my: 'Agizo Zangu', my_orders_empty: 'Huna agizo bado.',
    order_statuses: { pending: 'Inafanyiwa kazi', quoted: 'Imehifadhiwa kimasaa', paid: 'Imelipwa', escrow_hold: 'Escrow imeanzishwa', escrow_held: 'Escrow imeanzishwa', dispatched: 'Imesafirishwa', confirmed: 'Imetolewa', completed: 'Imekamilika', cancelled: 'Imeghairiwa', disputed: 'Kuna mzozo', refunded: 'Imerudishiwa', failed: 'Imeshindikana' },
    status_label: 'Hali', order_total: 'Jumla', order_date: 'Tarehe', order_id: 'Oda #', wa_cta: 'Wasiliana kwa WhatsApp',
    price: 'Bei', wait_fetch: 'Inapakia...', err_generic: 'Kuna tatizo. Jaribu tena.',
    theme_light: 'Mchana', theme_dark: 'Usiku', lang_label: 'Lugha', to_top: 'Juu',
  },
  en: {
    nav_home: 'Home', nav_categories: 'Categories', nav_orders: 'My Orders',
    nav_account: 'Account', nav_signin: 'Sign in', search_ph: 'Search products...',
    splash_p: 'Hi! The Soko Vibe shop is loading your products.',
    home_hero_kicker: 'Tanzania\'s marketplace', home_hero_title: 'Buy and sell anywhere in Tanzania.',
    home_hero_sub: 'Secure ClickPesa payments and escrow — pay only for what you receive.',
    home_new: 'New arrivals', home_browse: 'Browse', featured: 'Featured',
    categories: 'Categories', all: 'All', load_more: 'Load more',
    empty: 'No products', empty_filter: 'No matching products',
    view_detail: 'View', add_cart: 'Add to cart', buy_now: 'Buy now',
    in_stock: 'In stock', out_stock: 'Out of stock', qty: 'Qty',
    add_to_cart_ok: 'Added to cart', cart_title: 'Cart', cart_empty: 'Your cart is empty.',
    cart_browse: 'Browse products', cart_seller: 'Seller', remove: 'Remove',
    cart_total: 'Total', cart_checkout: 'Place order', back: 'Back',
    seller: 'Seller', condition: 'Condition', location: 'Location',
    description: 'Description', attributes: 'More info', variants: 'Variants',
    checkout_title: 'Checkout', checkout_addr: 'Delivery address',
    region: 'Region', district: 'District', ward: 'Ward', street: 'Street / road',
    landmarks: 'Landmarks (optional)', phone: 'Phone number (for USSD)',
    delivery: 'Delivery', deliver_local: 'Local delivery',
    fee_note: 'Platform fee (3.5%) + shipping are computed by the seller end',
    place_order: 'Place order & Pay', processing: 'Processing...',
    pay_wait: 'We sent a USSD prompt to your phone. Confirm, enter your PIN, pay.',
    pay_status_pending: 'Waiting for payment...', pay_status_paid: 'Payment received!',
    pay_done: 'Order complete — escrow activated.', pay_failed: 'Payment not received.',
    pay_new: 'Send USSD again', order_created: 'Order created.',
    need_auth: 'Sign in to continue.', signin_title: 'Sign in',
    signup_title: 'Create account', name: 'Full name', email: 'Email',
    password: 'Password', have_account: 'Have an account?', no_account: 'No account yet?',
    submit_signin: 'Sign in', submit_signup: 'Sign up', signout: 'Sign out',
    profile: 'Your account', orders_my: 'My Orders', my_orders_empty: 'No orders yet.',
    order_statuses: { pending: 'Pending', quoted: 'Price quoted', paid: 'Paid', escrow_hold: 'Escrow active', escrow_held: 'Escrow active', dispatched: 'Dispatched', confirmed: 'Released', completed: 'Completed', cancelled: 'Cancelled', disputed: 'Disputed', refunded: 'Refunded', failed: 'Failed' },
    status_label: 'Status', order_total: 'Total', order_date: 'Date', order_id: 'Order #',
    wa_cta: 'Chat on WhatsApp', price: 'Price', wait_fetch: 'Loading...',
    err_generic: 'Something went wrong. Try again.',
    theme_light: 'Light', theme_dark: 'Dark', lang_label: 'Language', to_top: 'Top',
  },
};

const SV_STATUS_ORDER = [
  'pending', 'quoted', 'paid', 'escrow_hold', 'escrow_held', 'dispatched',
  'confirmed', 'completed', 'disputed', 'refunded', 'cancelled', 'failed',
];