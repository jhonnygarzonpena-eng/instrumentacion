import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegistrarMultaTab extends StatefulWidget {
  const RegistrarMultaTab({super.key});

  @override
  State<RegistrarMultaTab> createState() => _RegistrarMultaTabState();
}

class _RegistrarMultaTabState extends State<RegistrarMultaTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  final TextEditingController _nuevoNombreController = TextEditingController();
  final TextEditingController _buscarNombreController = TextEditingController();
  final TextEditingController _valorController = TextEditingController();
  final TextEditingController _motivoController = TextEditingController();

  String? _categoriaSeleccionada = "Otra";
  List<Map<String, dynamic>> _sugerencias = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Limpiar controladores al cambiar de pestaña para evitar cruce de datos
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _nuevoNombreController.clear();
        _buscarNombreController.clear();
        setState(() => _sugerencias = []);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nuevoNombreController.dispose();
    _buscarNombreController.dispose();
    _valorController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  // Normalizador potente para ignorar tildes, diéresis y la letra Ñ
  String _normalizar(String texto) {
    return texto
        .toLowerCase()
        .trim()
        .replaceAll('ñ', 'n')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u');
  }

  // Buscador que filtra en la colección de movimientos
  Future<void> _buscarDeudoresInmune(String query) async {
    if (query.length < 2) {
      setState(() => _sugerencias = []);
      return;
    }

    final String queryNormal = _normalizar(query);

    final snapshot = await FirebaseFirestore.instance
        .collection('movimientos')
        .get();

    final Map<String, Map<String, dynamic>> tempMap = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final String nombreRaw = (data['nombreDeudor'] as String? ?? '').trim();
      if (nombreRaw.isEmpty) continue;

      final String nombreNormal = _normalizar(nombreRaw);
      final String nombreMostrar = nombreRaw.toUpperCase();

      // Comparación usando strings completamente normalizados
      if (!nombreNormal.contains(queryNormal)) continue;

      if (!tempMap.containsKey(nombreMostrar)) {
        tempMap[nombreMostrar] = {
          'nombre': nombreMostrar,
          'multas': 0,
          'pagos': 0,
        };
      }

      final valor = (data['valor'] ?? 0).toInt();
      if (data['tipo'] == 'multa') {
        tempMap[nombreMostrar]!['multas'] += valor;
      } else if (data['tipo'] == 'pago') {
        tempMap[nombreMostrar]!['pagos'] += valor;
      }
    }

    setState(() {
      _sugerencias = tempMap.values.toList();
    });
  }

  Future<void> _guardarMulta(bool esNuevo) async {
    // Selecciona el nombre dependiendo de la pestaña activa en el TabBar
    final nombre = esNuevo ? _nuevoNombreController.text.trim() : _buscarNombreController.text.trim();
    final valorText = _valorController.text.trim();

    if (nombre.isEmpty || valorText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Nombre y valor son obligatorios"), backgroundColor: Colors.orange),
      );
      return;
    }

    final valor = int.tryParse(valorText) ?? 0;

    setState(() => _isLoading = true);

    await FirebaseFirestore.instance.collection('movimientos').add({
      'tipo': 'multa',
      'nombreDeudor': nombre.toLowerCase(), // Se guarda ordenado en minúsculas en Firebase
      'valor': valor,
      'descripcion': _categoriaSeleccionada,
      'motivo': _motivoController.text.trim().isEmpty
          ? _categoriaSeleccionada ?? 'Sin motivo'
          : _motivoController.text.trim(),
      'fecha': Timestamp.now(),
      'registradoPor': 'admin',
    });

    // Limpieza completa del estado después de subir los datos
    _nuevoNombreController.clear();
    _buscarNombreController.clear();
    _valorController.clear();
    _motivoController.clear();
    setState(() {
      _sugerencias = [];
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Multa registrada correctamente"), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 0, // Eliminamos la barra de título superior para maximizar el espacio vertical
          backgroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: const [
              Tab(icon: Icon(Icons.person_add), text: "Nuevo Aprendiz"),
              Tab(icon: Icon(Icons.search), text: "Buscar Existente"),
            ],
          ),
        ),
        body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Nueva Multa", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    // Selector de contenido dinámico basado en la pestaña activa
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      constraints: const BoxConstraints(minHeight: 70),
                      child: [
                        // PESTAÑA 1: AGREGAR NUEVO APRENDIZ
                        TextField(
                          controller: _nuevoNombreController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: "Nombre del Nuevo Aprendiz",
                            hintText: "Escribe el nombre completo...",
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                        ),

                        // PESTAÑA 2: BUSCAR APRENDIZ EXISTENTE (Autocomplete predictivo fijo)
                        Autocomplete<Map<String, dynamic>>(
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.length < 2) return const Iterable.empty();
                            return _sugerencias;
                          },
                          displayStringForOption: (deudor) => deudor['nombre'],
                          onSelected: (Map<String, dynamic> deudor) {
                            _buscarNombreController.text = deudor['nombre'];
                          },
                          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              textCapitalization: TextCapitalization.characters,
                              onChanged: (val) {
                                _buscarNombreController.text = val;
                                _buscarDeudoresInmune(val);
                              },
                              decoration: const InputDecoration(
                                labelText: "Buscar Aprendiz",
                                hintText: "Escribe para buscar (ej: jefer pe)...",
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: MediaQuery.of(context).size.width * 0.92,
                                  constraints: const BoxConstraints(maxHeight: 200), // Altura óptima para evitar overflows
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(8),
                                    itemCount: options.length,
                                    itemBuilder: (context, index) {
                                      final deudor = options.elementAt(index);
                                      final saldo = deudor['multas'] - deudor['pagos'];

                                      return ListTile(
                                        leading: Icon(
                                          saldo > 0 ? Icons.warning_amber_rounded : Icons.paid,
                                          color: saldo > 0 ? Colors.red : Colors.green,
                                        ),
                                        title: Text(deudor['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: Text("Multas: \$${deudor['multas']} | Pagos: \$${deudor['pagos']}"),
                                        trailing: Text(
                                          "\$$saldo",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: saldo > 0 ? Colors.red : Colors.green,
                                          ),
                                        ),
                                        onTap: () => onSelected(deudor),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ][_tabController.index],
                    ),

                    const SizedBox(height: 16),

                    // CAMPOS COMUNES DEL FORMULARIO
                    DropdownButtonFormField<String>(
                      initialValue: _categoriaSeleccionada,
                      decoration: const InputDecoration(
                        labelText: "Categoría de la Multa",
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: "Uniforme", child: Text("Uniforme")),
                        DropdownMenuItem(value: "Aseo", child: Text("Aseo")),
                        DropdownMenuItem(value: "Grosería", child: Text("Grosería")),
                        DropdownMenuItem(value: "Otra", child: Text("Otra")),
                      ],
                      onChanged: (value) => setState(() => _categoriaSeleccionada = value),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: _valorController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: "Valor (COP)",
                        prefixText: "\$ ",
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 14),

                    TextField(
                      controller: _motivoController,
                      decoration: const InputDecoration(
                        labelText: "Motivo adicional (Opcional)",
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),

                    const SizedBox(height: 24),

                    // BOTÓN DE GUARDADO ADAPTATIVO
                    SizedBox(
                      width: double.infinity,
                      height: 50, // Altura compacta para prevenir desbordes de pantalla
                      child: ElevatedButton.icon(
                        onPressed: () => _guardarMulta(_tabController.index == 0),
                        icon: const Icon(Icons.save),
                        label: const Text("GUARDAR REGISTRO", style: TextStyle(fontSize: 18)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}