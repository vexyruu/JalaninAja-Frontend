
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'map_screen.dart'; 
import 'report_page.dart';
import 'user_page.dart';
import 'auth_screen.dart';
import 'config_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const bool isProduction = bool.fromEnvironment('dart.vm.product');
  await dotenv.load(fileName: isProduction ? '.env.prod' : '.env.dev');

  try {
    await ConfigService.instance.initialize();

    await Supabase.initialize(
      url: ConfigService.instance.supabaseUrl,
      anonKey: ConfigService.instance.supabaseAnonKey,
    );

    runApp(const MyApp());
  } catch (e) {
    runApp(ErrorApp(errorMessage: e.toString()));
  }
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const primaryGreen = Color(0xFF2E7D32);
    const darkText = Color(0xFF1a1a1a);
    const bodyText = Color(0xFF4f4f4f);
    const lightText = Color(0xFF828282);
    const backgroundColor = Color(0xFFF8F9FA);

    return MaterialApp(
      title: 'JalaninAja',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryGreen,
          primary: primaryGreen,
          background: backgroundColor,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.black,
          onBackground: darkText,
          onSurface: darkText,
        ),
        scaffoldBackgroundColor: backgroundColor,
        textTheme: GoogleFonts.interTextTheme(textTheme).copyWith(

          titleLarge: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: darkText),

          titleMedium: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: darkText),

          titleSmall: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: darkText),

          bodyLarge: GoogleFonts.inter(fontSize: 16, color: bodyText),

          bodyMedium: GoogleFonts.inter(fontSize: 14, color: bodyText),

          bodySmall: GoogleFonts.inter(fontSize: 12, color: lightText),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: darkText,
          elevation: 1,
          surfaceTintColor: Colors.white,
          shadowColor: Colors.grey.withOpacity(0.2),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          selectedItemColor: primaryGreen,
          unselectedItemColor: Colors.grey[600],
          backgroundColor: Colors.white,
          selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.inter(),
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data?.session != null) {
            return const MainScreen();
          }
          return const AuthScreen();
        },
      ),
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String errorMessage;
  const ErrorApp({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Failed to start the application:\n\n$errorMessage',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    MapScreen(),
    ReportPage(),
    UserPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.report_problem_outlined),
            label: 'Report',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}