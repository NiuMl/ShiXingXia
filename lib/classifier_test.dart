import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ml_algo/ml_algo.dart';
import 'package:ml_dataframe/ml_dataframe.dart';

/// Optional test widget to verify KNN classifier works with your data
/// Add this to your main.dart for testing, then remove it
class TestKNNClassifier extends StatefulWidget {
  const TestKNNClassifier({super.key});

  @override
  State<TestKNNClassifier> createState() => _TestKNNClassifierState();
}

class _TestKNNClassifierState extends State<TestKNNClassifier> {
  String _status = 'Not started';
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;

  Future<void> _testClassifier() async {
    setState(() {
      _isLoading = true;
      _status = 'Loading training data...';
      _results.clear();
    });

    try {
      // Load CSV
      final csvContent = await rootBundle.loadString('assets/pushup_features_binary.csv');
      
      setState(() => _status = 'Parsing CSV...');
      
      // Parse into DataFrame
      final allData = DataFrame.fromRawCsv(
        csvContent,
        headerExists: true,
        fieldDelimiter: ',',
      );

      setState(() => _status = 'Training KNN classifier...');
      
      // Split: 80% train, 20% test
      final shuffled = allData.shuffle();
      final trainSize = (shuffled.rows.length * 0.8).round();
      final trainRows = shuffled.rows.take(trainSize).toList();
      final testRows = shuffled.rows.skip(trainSize).toList();
      
      final trainData = DataFrame(trainRows, header: shuffled.header);
      final testData = DataFrame(testRows, header: shuffled.header);

      setState(() => _status = 'Training on ${trainRows.length} samples...');

      // Train classifier
      final classifier = KnnClassifier(
        trainData,
        'pose',
        3, // k=3
        kernel: KernelType.gaussian,
        distance: Distance.euclidean,
      );

      setState(() => _status = 'Testing on ${testRows.length} samples...');

      // Test on held-out data
      final predictions = classifier.predict(testData);
      final probabilities = classifier.predictProbabilities(testData);

      // Calculate accuracy
      int correct = 0;
      final results = <Map<String, dynamic>>[];
      
      for (int i = 0; i < testRows.length; i++) {
        final actualClass = testRows[i].last as num; // Last column is 'pose'
        final predictedClass = predictions.rows.elementAt(i).first as num;
        final probRow = probabilities.rows.elementAt(i).toList();
        final confidence = probRow.reduce((a, b) => (a as num) > (b as num) ? a : b) as num;
        
        if (actualClass == predictedClass) correct++;
        
        results.add({
          'actual': actualClass == 1 ? 'UP' : 'DOWN',
          'predicted': predictedClass == 1 ? 'UP' : 'DOWN',
          'confidence': (confidence.toDouble() * 100).toStringAsFixed(1),
          'correct': actualClass == predictedClass,
        });
      }

      final accuracy = (correct / testRows.length * 100).toStringAsFixed(1);

      setState(() {
        _status = 'Accuracy: $accuracy% ($correct/${testRows.length})';
        _results = results.take(10).toList(); // Show first 10
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test KNN Classifier')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(_status),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _testClassifier,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Run Test'),
            ),
            const SizedBox(height: 16),
            if (_results.isNotEmpty) ...[
              const Text(
                'Sample Predictions (first 10):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final result = _results[index];
                    final isCorrect = result['correct'] as bool;
                    return Card(
                      color: isCorrect
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      child: ListTile(
                        leading: Icon(
                          isCorrect ? Icons.check_circle : Icons.error,
                          color: isCorrect ? Colors.green : Colors.red,
                        ),
                        title: Text(
                          'Actual: ${result['actual']} → Predicted: ${result['predicted']}',
                        ),
                        trailing: Text('${result['confidence']}%'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Add this to your main.dart for testing:
/*
void main() {
  runApp(MaterialApp(
    home: TestKNNClassifier(),
  ));
}
*/