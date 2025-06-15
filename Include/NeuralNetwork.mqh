//+------------------------------------------------------------------+
//|                                                NeuralNetwork.mqh |
//|                                                 William Nicholas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "William Nicholas"
#property link      "https://www.mql5.com"
#include <Math\Stat\Normal.mqh>

class NeuralNetwork {
private:
   int    m_maxiters;
   double m_beta_1;
   double m_beta_2;
   bool   m_verbose;
   double m_LearningRate;
   int    m_depth;      // Input dimension (columns)
   int    m_deep;       // Number of hidden neurons
   int    m_outDim;     // Output dimension
   double m_alpha;      // Convergence threshold
   double m_lambda;     // L2 regularization parameter
   string m_weight1_file; // File name for W_1
   string m_weight2_file; // File name for W_2
   matrix m_input;
   matrix m_pred_input;
   matrix m_z_2;
   matrix m_a_2; 
   matrix m_z_3;
   matrix m_yHat;
   matrix z_3_prime;
   matrix z_2_prime;
   matrix delta2;
   matrix delta3;
   matrix dJdW1;
   matrix dJdW2;
   matrix y_cor;

   matrix Forward_Prop(matrix &Input);
   double Cost(matrix &Input, matrix &y_cor);
   double Sigmoid(double x);
   double Sigmoid_Prime(double x);     
   void   MatrixRandom(matrix &m);
   matrix MatrixSigmoidPrime(matrix &m);
   matrix MatrixSigmoid(matrix &m);
   void   ComputeDerivatives(matrix &Input, matrix &y_);
   double MatrixMeanSquare(matrix &m); // For L2 regularization
   matrix MatrixSqrt(matrix &m);       // For element-wise sqrt

public:
   matrix W_1;
   matrix W_2;
   
   NeuralNetwork(int in_DimensionRow, int in_DimensionCol, int Number_of_Neurons, int out_Dimension, 
                 double alpha, double LearningRate, bool Verbose, double beta_1, double beta_2, 
                 int max_iterations, double lambda = 0.01, 
                 string weight1_file = "Weights_1.txt", string weight2_file = "Weights_2.txt");
   void   Train(matrix& Input, matrix &correct_Val); 
   int    Sgn(double Value);
   matrix Prediction(matrix& Input); 
   void   ResetWeights();
   bool   WriteWeights();
   bool   LoadWeights();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
NeuralNetwork::NeuralNetwork(int in_DimensionRow, int in_DimensionCol, int Number_of_Neurons, 
                             int out_Dimension, double alpha, double LearningRate, bool Verbose, 
                             double beta_1, double beta_2, int max_iterations, double lambda, 
                             string weight1_file, string weight2_file) {
   m_depth = in_DimensionCol;
   m_deep  = Number_of_Neurons;
   m_outDim = out_Dimension;
   m_alpha = alpha;
   m_LearningRate = LearningRate;
   m_beta_1 = beta_1;
   m_beta_2 = beta_2;
   m_maxiters = max_iterations;
   m_verbose = Verbose;
   m_lambda = lambda;
   m_weight1_file = weight1_file;
   m_weight2_file = weight2_file;
   
   matrix random_W1(m_depth, m_deep);
   matrix random_W2(m_deep, m_outDim);
   
   MatrixRandom(random_W1);
   MatrixRandom(random_W2);
   
   W_1 = random_W1;
   W_2 = random_W2;
   
   if (m_verbose) {
      Print("Initialized W_1: ", W_1.Rows(), "x", W_1.Cols());
      Print("Initialized W_2: ", W_2.Rows(), "x", W_2.Cols());
   }
}

//+------------------------------------------------------------------+
//| Load weights from files                                          |
//+------------------------------------------------------------------+
bool NeuralNetwork::LoadWeights(void) {
   int handle = FileOpen(m_weight1_file, FILE_READ | FILE_CSV);
   if (handle == INVALID_HANDLE) {
      Print("Failed to open ", m_weight1_file);
      return false;
   }
   W_1.Init(m_depth, m_deep);
   for (ulong r = 0; r < W_1.Rows(); r++) {
      for (ulong c = 0; c < W_1.Cols(); c++) {
         string value = FileReadString(handle);
         if (value == "") {
            Print("Error reading W_1 at [", r, ",", c, "]");
            FileClose(handle);
            return false;
         }
         W_1[r][c] = StringToDouble(value);
      }
   }
   FileClose(handle);

   handle = FileOpen(m_weight2_file, FILE_READ | FILE_CSV);
   if (handle == INVALID_HANDLE) {
      Print("Failed to open ", m_weight2_file);
      return false;
   }
   W_2.Init(m_deep, m_outDim);
   for (ulong r = 0; r < W_2.Rows(); r++) {
      for (ulong c = 0; c < W_2.Cols(); c++) {
         string value = FileReadString(handle);
         if (value == "") {
            Print("Error reading W_2 at [", r, ",", c, "]");
            FileClose(handle);
            return false;
         }
         W_2[r][c] = StringToDouble(value);
      }
   }
   FileClose(handle);
   return true;
}

//+------------------------------------------------------------------+
//| Save weights to files                                            |
//+------------------------------------------------------------------+
bool NeuralNetwork::WriteWeights(void) {
   int handle_w1 = FileOpen(m_weight1_file, FILE_WRITE | FILE_CSV);
   if (handle_w1 == INVALID_HANDLE) {
      Print("Failed to open ", m_weight1_file);
      return false;
   }
   for (ulong r = 0; r < W_1.Rows(); r++) {
      for (ulong c = 0; c < W_1.Cols(); c++) {
         FileWrite(handle_w1, DoubleToString(W_1[r][c], 8));
      }
   }
   FileClose(handle_w1);

   int handle_w2 = FileOpen(m_weight2_file, FILE_WRITE | FILE_CSV);
   if (handle_w2 == INVALID_HANDLE) {
      Print("Failed to open ", m_weight2_file);
      return false;
   }
   for (ulong r = 0; r < W_2.Rows(); r++) {
      for (ulong c = 0; c < W_2.Cols(); c++) {
         FileWrite(handle_w2, DoubleToString(W_2[r][c], 8));
      }
   }
   FileClose(handle_w2);
   return true;
}

//+------------------------------------------------------------------+
//| Reset weights to random values                                   |
//+------------------------------------------------------------------+
void NeuralNetwork::ResetWeights(void) {
   matrix random_W1(m_depth, m_deep);
   matrix random_W2(m_deep, m_outDim);
   
   MatrixRandom(random_W1);
   MatrixRandom(random_W2);
   
   W_1 = random_W1;
   W_2 = random_W2;
   
   if (m_verbose) Print("Weights reset");
}

//+------------------------------------------------------------------+
//| Compute derivatives for backpropagation                          |
//+------------------------------------------------------------------+
void NeuralNetwork::ComputeDerivatives(matrix &Input, matrix &y_) {
   matrix X = Input;
   matrix Y = y_;  
   
   m_yHat = Forward_Prop(X); 
   
   matrix cost = -1 * (Y - m_yHat);
   z_3_prime = MatrixSigmoidPrime(m_z_3);
   delta3 = cost * z_3_prime;
   dJdW2 = m_a_2.Transpose().MatMul(delta3); 
   
   z_2_prime = MatrixSigmoidPrime(m_z_2);
   delta2 = delta3.MatMul(W_2.Transpose()) * z_2_prime;
   dJdW1 = m_input.Transpose().MatMul(delta2);
}

//+------------------------------------------------------------------+
//| Train the neural network using Adam optimizer                    |
//+------------------------------------------------------------------+
void NeuralNetwork::Train(matrix &Input, matrix &correct_Val) {
   // Validate input dimensions
   if (Input.Cols() != m_depth || correct_Val.Cols() != m_outDim || Input.Rows() != correct_Val.Rows()) {
      Print("Invalid input or output dimensions. Expected Input: [", Input.Rows(), ",", m_depth, 
            "], Output: [", correct_Val.Rows(), ",", m_outDim, "]");
      return;
   }

   y_cor = correct_Val;
   int iterations = 0;
   
   matrix mt_1(W_1.Rows(), W_1.Cols()), vt_1(W_1.Rows(), W_1.Cols());
   matrix mt_2(W_2.Rows(), W_2.Cols()), vt_2(W_2.Rows(), W_2.Cols());
   mt_1.Fill(0); vt_1.Fill(0); mt_2.Fill(0); vt_2.Fill(0);
   double epsilon = 1e-8;

   while (iterations < m_maxiters) {
      // Compute forward propagation and cost
      m_yHat = Forward_Prop(Input);
      ComputeDerivatives(Input, y_cor);
      double J = Cost(Input, y_cor); // Declare and assign J before use

      // Check convergence
      if (J < m_alpha) {
         if (m_verbose) Print("Converged at iteration ", iterations, " with cost: ", J);
         break;
      }

      // Adam update
      mt_1 = m_beta_1 * mt_1 + (1 - m_beta_1) * dJdW1;
      vt_1 = m_beta_2 * vt_1 + (1 - m_beta_2) * (dJdW1 * dJdW1);
      matrix mt_1_hat = mt_1 / (1 - MathPow(m_beta_1, iterations + 1));
      matrix vt_1_hat = vt_1 / (1 - MathPow(m_beta_2, iterations + 1));
      W_1 -= m_LearningRate * (mt_1_hat / (MatrixSqrt(vt_1_hat) + epsilon));

      mt_2 = m_beta_1 * mt_2 + (1 - m_beta_1) * dJdW2;
      vt_2 = m_beta_2 * vt_2 + (1 - m_beta_2) * (dJdW2 * dJdW2);
      matrix mt_2_hat = mt_2 / (1 - MathPow(m_beta_1, iterations + 1));
      matrix vt_2_hat = vt_2 / (1 - MathPow(m_beta_2, iterations + 1));
      W_2 -= m_LearningRate * (mt_2_hat / (MatrixSqrt(vt_2_hat) + epsilon));

      iterations++;
      if (m_verbose && iterations % 100 == 0) {
         Print("Iteration: ", iterations, " Cost: ", J);
      }
   }
   
   if (m_verbose) {
      Print("Final iterations: ", iterations, " Cost: ", Cost(Input, y_cor));
   }
}

//+------------------------------------------------------------------+
//| Make predictions                                                 |
//+------------------------------------------------------------------+
matrix NeuralNetwork::Prediction(matrix& Input) {
   if (Input.Cols() != m_depth) {
      Print("Invalid input dimensions for prediction. Expected [", Input.Rows(), ",", m_depth, "]");
      matrix empty(Input.Rows(), m_outDim); // Initialize with proper dimensions
      empty.Fill(0);
      return empty;
   }
   
   m_pred_input = Input;
   matrix pred_z_2 = m_pred_input.MatMul(W_1);
   matrix pred_a_2 = MatrixSigmoid(pred_z_2);
   matrix pred_z_3 = pred_a_2.MatMul(W_2);
   matrix pred_yHat = MatrixSigmoid(pred_z_3);
   
   return pred_yHat;
}

//+------------------------------------------------------------------+
//| Compute cost (MSE with L2 regularization)                        |
//+------------------------------------------------------------------+
double NeuralNetwork::Cost(matrix &Input, matrix &y_) {
   matrix X = Input;   
   matrix Y = y_;
   m_yHat = Forward_Prop(X);
   
   matrix temp = (Y - m_yHat);
   temp = temp * temp;  // Element-wise square
   double l2 = m_lambda * (MatrixMeanSquare(W_1) + MatrixMeanSquare(W_2)); // L2 regularization
   double J = 0.5 * (temp.Sum() / (temp.Cols() * temp.Rows())) + l2;
   return J; 
}

//+------------------------------------------------------------------+
//| Compute mean square of matrix elements                           |
//+------------------------------------------------------------------+
double NeuralNetwork::MatrixMeanSquare(matrix &m) {
   double sum = 0;
   ulong rows = m.Rows();
   ulong cols = m.Cols();
   for (ulong r = 0; r < rows; r++) {
      for (ulong c = 0; c < cols; c++) {
         sum += m[r][c] * m[r][c];
      }
   }
   return sum / (rows * cols);
}

//+------------------------------------------------------------------+
//| Apply element-wise square root to matrix                         |
//+------------------------------------------------------------------+
matrix NeuralNetwork::MatrixSqrt(matrix &m) {
   matrix result;
   result.Init(m.Rows(), m.Cols());
   for (ulong r = 0; r < m.Rows(); r++) {
      for (ulong c = 0; c < m.Cols(); c++) {
         result[r][c] = MathSqrt(MathMax(m[r][c], 0)); // Ensure non-negative for sqrt
      }
   }
   return result;
}

//+------------------------------------------------------------------+
//| Forward propagation                                              |
//+------------------------------------------------------------------+
matrix NeuralNetwork::Forward_Prop(matrix& Input) {
   m_input = Input;
   m_z_2 = m_input.MatMul(W_1);
   m_a_2 = MatrixSigmoid(m_z_2);
   m_z_3 = m_a_2.MatMul(W_2);
   matrix yHat = MatrixSigmoid(m_z_3);
   return yHat;
}

//+------------------------------------------------------------------+
//| Sigmoid activation function                                       |
//+------------------------------------------------------------------+
double NeuralNetwork::Sigmoid(double x) {
   return 1.0 / (1.0 + MathExp(-x));
}

//+------------------------------------------------------------------+
//| Derivative of sigmoid function                                    |
//+------------------------------------------------------------------+
double NeuralNetwork::Sigmoid_Prime(double x) {
   double sigmoid = Sigmoid(x);
   return sigmoid * (1 - sigmoid);
}

//+------------------------------------------------------------------+
//| Sign function                                                    |
//+------------------------------------------------------------------+
int NeuralNetwork::Sgn(double Value) {
   return Value > 0 ? 1 : -1;
}

//+------------------------------------------------------------------+
//| Initialize matrix with random normal values                      |
//+------------------------------------------------------------------+
void NeuralNetwork::MatrixRandom(matrix& m) {
   int error;
   for (ulong r = 0; r < m.Rows(); r++) {
      for (ulong c = 0; c < m.Cols(); c++) {
         m[r][c] = MathRandomNormal(0, 1, error);
      }
   }
}

//+------------------------------------------------------------------+
//| Apply sigmoid to matrix elements                                  |
//+------------------------------------------------------------------+
matrix NeuralNetwork::MatrixSigmoid(matrix& m) {
   matrix m_2;
   m_2.Init(m.Rows(), m.Cols());
   for (ulong r = 0; r < m.Rows(); r++) {
      for (ulong c = 0; c < m.Cols(); c++) {
         m_2[r][c] = Sigmoid(m[r][c]);
      }
   }
   return m_2;
}

//+------------------------------------------------------------------+
//| Apply sigmoid prime to matrix elements                           |
//+------------------------------------------------------------------+
matrix NeuralNetwork::MatrixSigmoidPrime(matrix& m) {
   matrix m_2;
   m_2.Init(m.Rows(), m.Cols());
   for (ulong r = 0; r < m.Rows(); r++) {
      for (ulong c = 0; c < m.Cols(); c++) {
         m_2[r][c] = Sigmoid_Prime(m[r][c]);
      }
   }
   return m_2;
}