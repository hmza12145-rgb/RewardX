import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    runApp(const RewardXApp());
  } catch (e) {
    runApp(StartupErrorApp(error: e.toString()));
  }
}

class StartupErrorApp extends StatelessWidget {
  final String error;

  const StartupErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0D17),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                'RewardX startup error:\n\n$error',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RewardXApp extends StatelessWidget {
  const RewardXApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RewardX',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B0D17),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8B5CF6),
        brightness: Brightness.dark,
      ),
    ),
    home: const AuthGate(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return snapshot.data == null ? const SignInPage() : const Dashboard();
    },
  );
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;

  Future<void> runAuth(Future<void> Function() action) async {
    setState(() { busy = true; error = null; });
    try { await action(); }
    on FirebaseAuthException catch (e) { setState(() => error = e.message ?? e.code); }
    catch (e) { setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> googleLogin() async {
    if (kIsWeb) {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      return;
    }
    await GoogleSignIn.instance.initialize();
    final account = await GoogleSignIn.instance.authenticate();
    final auth = account.authentication;
    final credential = GoogleAuthProvider.credential(idToken: auth.idToken);
    await FirebaseAuth.instance.signInWithCredential(credential);
  }

  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.bolt, size: 58, color: Color(0xFFA78BFA)),
            const SizedBox(height: 8),
            const Text('RewardX', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
            const Text('Earn points. Redeem real rewards.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 32),
            TextField(controller: email, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 10),
              child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : () => runAuth(() async {
                await FirebaseAuth.instance.signInWithEmailAndPassword(
                  email: email.text.trim(), password: password.text);
              }),
              child: Text(busy ? 'Please wait...' : 'Sign in')),
            OutlinedButton(
              onPressed: busy ? null : () => runAuth(() async {
                await FirebaseAuth.instance.createUserWithEmailAndPassword(
                  email: email.text.trim(), password: password.text);
              }),
              child: const Text('Create email account')),
            OutlinedButton.icon(
              onPressed: busy ? null : () => runAuth(googleLogin),
              icon: const Icon(Icons.account_circle), label: const Text('Continue with Google')),
            const SizedBox(height: 12),
            const Text('Use your own account. Never share passwords or gift-card codes.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
      ),
    ),
  );
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
    // Create the initial profile through a trusted callable; clients cannot write balances.
    unawaited(FirebaseFunctions.instance.httpsCallable('ensureProfile').call().then<void>((_) {}, onError: (_) {}));
    return Scaffold(
      appBar: AppBar(title: const Text('RewardX', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(onPressed: () => FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout))]),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDoc.snapshots(),
        builder: (context, snap) {
          final points = (snap.data?.data()?['points'] as num?)?.toInt() ?? 0;
          return ListView(padding: const EdgeInsets.all(18), children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(colors: [Color(0xFF6D28D9), Color(0xFF2563EB)])),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('YOUR REWARD BALANCE'),
                const SizedBox(height: 10),
                Text('$points points', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                Text(user.email ?? user.displayName ?? 'RewardX member'),
              ]),
            ),
            const SizedBox(height: 18),
            const Text('Earn points', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Card(child: ListTile(
              leading: Icon(Icons.ondemand_video, color: Color(0xFFA78BFA)),
              title: Text('Rewarded video ads'),
              subtitle: Text('Android ad integration must be configured and SSV verified.'),
            )),
            const Card(child: ListTile(
              leading: Icon(Icons.task_alt, color: Color(0xFFA78BFA)),
              title: Text('Verified tasks'),
              subtitle: Text('Task rewards are issued by trusted server workflows.'),
            )),
            const SizedBox(height: 18),
            const Text('Redeem', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const RedeemButton(),
            const SizedBox(height: 18),
            FutureBuilder<IdTokenResult>(
              future: user.getIdTokenResult(true),
              builder: (context, claim) {
                if (claim.data?.claims?['admin'] == true) {
                  return Card(child: ListTile(
                    leading: const Icon(Icons.admin_panel_settings, color: Color(0xFFA78BFA)),
                    title: const Text('Admin panel'),
                    subtitle: const Text('Manage gift-card inventory'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AdminPanel())),
                  ));
                }
                return const SizedBox.shrink();
              },
            ),
            const SizedBox(height: 18),
            const Text('Wallet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid)
                .collection('wallet').orderBy('claimedAt', descending: true).snapshots(),
              builder: (context, wallet) {
                if (!wallet.hasData) return const LinearProgressIndicator();
                if (wallet.data!.docs.isEmpty) return const Text('No rewards claimed yet.');
                return Column(children: wallet.data!.docs.map((d) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.card_giftcard, color: Color(0xFFA78BFA)),
                    title: Text(d.data()['label'] ?? 'Gift card'),
                    subtitle: Text('Code: ${d.data()['code'] ?? 'Pending'}'),
                  ),
                )).toList());
              },
            ),
          ]);
        },
      ),
    );
  }
}

class RedeemButton extends StatefulWidget {
  const RedeemButton({super.key});
  @override
  State<RedeemButton> createState() => _RedeemButtonState();
}

class _RedeemButtonState extends State<RedeemButton> {
  bool busy = false;
  String? result;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Google Play gift card (India)',
          style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Availability and stock depend on authorized supplier inventory.',
          style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : () async {
            setState(() { busy = true; result = null; });
            try {
              // Backend validates stock, points and user eligibility in a transaction.
              // Configure the product ID in Firestore / Cloud Functions before enabling.
              final response = await FirebaseFunctions.instance
                .httpsCallable('redeemGiftCard').call({'productId': 'google_play_inr_100'});
              setState(() => result = 'Claim successful: ${response.data['label']}');
            } on FirebaseFunctionsException catch (e) {
              setState(() => result = e.message ?? e.code);
            } finally { if (mounted) setState(() => busy = false); }
          },
          child: Text(busy ? 'Checking...' : 'Redeem 100 INR card'),
        ),
        if (result != null) Padding(padding: const EdgeInsets.only(top: 8),
          child: Text(result!)),
      ],
    )),
  );
}


class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});
  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final code = TextEditingController();
  final label = TextEditingController(text: 'Google Play ₹100');
  final product = TextEditingController(text: 'google_play_inr_100');
  final points = TextEditingController(text: '1000');
  bool busy = false;
  String? message;

  @override
  void dispose() {
    code.dispose(); label.dispose(); product.dispose(); points.dispose();
    super.dispose();
  }

  Future<void> addStock() async {
    setState(() { busy = true; message = null; });
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('addGiftCard').call({
        'code': code.text.trim(),
        'label': label.text.trim(),
        'productId': product.text.trim(),
        'pointsCost': int.parse(points.text.trim()),
        'region': 'IN',
      });
      setState(() { message = 'Inventory item added: ${result.data['cardId']}'; code.clear(); });
    } catch (e) {
      setState(() => message = 'Could not add item: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Widget field(TextEditingController c, String labelText, {bool secret = false, TextInputType? type}) =>
    Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(
      controller: c, obscureText: secret, keyboardType: type,
      decoration: InputDecoration(labelText: labelText, border: const OutlineInputBorder()),
    ));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('RewardX Admin')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Add gift-card stock', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Only authorized admins can add codes. Codes are stored in the private server inventory.',
        style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 18),
      field(code, 'Unused gift-card code', secret: true),
      field(label, 'Display label'),
      field(product, 'Product ID'),
      field(points, 'Points cost', type: TextInputType.number),
      FilledButton(onPressed: busy ? null : addStock,
        child: Text(busy ? 'Saving...' : 'Add to inventory')),
      if (message != null) Padding(padding: const EdgeInsets.only(top: 12), child: SelectableText(message!)),
    ]),
  );
}
