import math
import os
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_caching import Cache
from flask_bcrypt import Bcrypt
from datetime import datetime, timedelta
import pandas as pd
from io import BytesIO
import jwt
from functools import wraps

app = Flask(__name__)
CORS(app)

# Secret key for JWT
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', 'dev-secret-key-change-in-production')

# --- Database Configuration ---
db_user = os.getenv('POSTGRES_USER', 'user')
db_password = os.getenv('POSTGRES_PASSWORD', 'password')
db_host = os.getenv('POSTGRES_HOST', 'db')
db_port = os.getenv('POSTGRES_PORT', 5432)
db_name = os.getenv('POSTGRES_DB', 'db')
db_url = f"postgresql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"

# Support both custom build and DATABASE_URL env variable
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL', db_url)
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)
bcrypt = Bcrypt(app)

# --- Rate Limiting Configuration ---
limiter = Limiter(
    app=app,
    key_func=get_remote_address,
    default_limits=["200 per day", "50 per hour"],
    storage_uri="memory://"
)

# --- Caching Configuration ---
cache = Cache(app, config={
    'CACHE_TYPE': 'SimpleCache',  # Will upgrade to Redis later
    'CACHE_DEFAULT_TIMEOUT': 300
})

class Calculation(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    category = db.Column(db.String(50), nullable=False)
    inputs = db.Column(db.JSON, nullable=False)
    results = db.Column(db.JSON, nullable=False)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=True)  # Optional user association

    def __repr__(self):
        return f'<Calculation {self.id} - {self.category}>'
    
    def to_dict(self):
        """Convert calculation to dictionary for JSON response."""
        return {
            'id': self.id,
            'category': self.category,
            'inputs': self.inputs,
            'results': self.results,
            'timestamp': self.timestamp.isoformat(),
            'user_id': self.user_id
        }

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    calculations = db.relationship('Calculation', backref='user', lazy=True)

    def __repr__(self):
        return f'<User {self.username}>'
    
    def to_dict(self):
        return {
            'id': self.id,
            'username': self.username,
            'email': self.email,
            'created_at': self.created_at.isoformat()
        }

with app.app_context():
    db.create_all()

# --- Authentication Helper Functions ---
def generate_token(user_id):
    """Generate JWT token for user."""
    payload = {
        'user_id': user_id,
        'exp': datetime.utcnow() + timedelta(days=7)
    }
    return jwt.encode(payload, app.config['SECRET_KEY'], algorithm='HS256')

def require_auth(f):
    """Decorator to require authentication for endpoints."""
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token:
            return jsonify({'error': 'No token provided'}), 401
        
        # Remove 'Bearer ' prefix if present
        if token.startswith('Bearer '):
            token = token[7:]
        
        try:
            payload = jwt.decode(token, app.config['SECRET_KEY'], algorithms=['HS256'])
            current_user = User.query.get(payload['user_id'])
            if not current_user:
                return jsonify({'error': 'User not found'}), 401
        except jwt.ExpiredSignatureError:
            return jsonify({'error': 'Token expired'}), 401
        except jwt.InvalidTokenError:
            return jsonify({'error': 'Invalid token'}), 401
        
        return f(current_user, *args, **kwargs)
    return decorated

# --- Multipliers from your list ---
# --- Input Validation ---
def validate_supplement_inputs(data):
    """Validate supplement calculation inputs."""
    required_fields = ['purchasePrice', 'fxRate', 'weightGrams', 'count', 'dailyDose']
    for field in required_fields:
        if field not in data:
            raise ValueError(f"Missing required field: {field}")
        value = data[field]
        if not isinstance(value, (int, float, str)):
            raise ValueError(f"Invalid type for {field}")
        # Convert string to float if needed
        try:
            float_val = float(value)
            if float_val < 0:
                raise ValueError(f"Negative value not allowed for {field}")
        except (ValueError, TypeError):
            raise ValueError(f"Invalid numeric value for {field}")
    return True

def validate_device_inputs(data):
    """Validate device calculation inputs."""
    required_fields = ['purchasePrice', 'fxRate', 'lengthCm', 'widthCm', 'heightCm', 'weightKg']
    for field in required_fields:
        if field not in data:
            raise ValueError(f"Missing required field: {field}")
        value = data[field]
        if not isinstance(value, (int, float, str)):
            raise ValueError(f"Invalid type for {field}")
        try:
            float_val = float(value)
            if float_val < 0:
                raise ValueError(f"Negative value not allowed for {field}")
        except (ValueError, TypeError):
            raise ValueError(f"Invalid numeric value for {field}")
    return True

# --- Multipliers from your list ---
MULTIPLIERS = {
    'maleSupport': { 'Yes': 1.25, 'No': 1 },
    'productShape': {
        'Capsules/Tablets': 1, 'Softgels/Chews': 1, 'Powder/Creamy': 1,
        'Gummies': 1.1, 'Liquid': 1.05, 'Injection': 1.2
    },
    'bottleSize': { 'Small': 0.9, 'Normal': 1, 'Big': 1.1, 'Massive': 1.2 },
    'packingMaterial': { 'Plastic': 1, 'Glass': 1.12, 'Paper': 1.06 },
    'importOrigin': { 'US': 1, 'UK': 1.25, 'EU': 1.1 }
}

def calculate_supplement_price(inputs):
    # Defaults
    purchasePrice = float(inputs.get('purchasePrice', 0))
    fxRate = float(inputs.get('fxRate', 50))
    weightGrams = float(inputs.get('weightGrams', 0))
    count = float(inputs.get('count', 0))
    dailyDose = float(inputs.get('dailyDose', 1))
    
    # Get Multipliers
    shapeMult = MULTIPLIERS['productShape'].get(inputs.get('productShape'), 1)
    packMult = MULTIPLIERS['packingMaterial'].get(inputs.get('packingMaterial'), 1)
    sizeMult = MULTIPLIERS['bottleSize'].get(inputs.get('bottleSize'), 1)
    maleMult = MULTIPLIERS['maleSupport'].get(inputs.get('isMaleSupport'), 1)
    originMult = MULTIPLIERS['importOrigin'].get(inputs.get('importFrom'), 1)

    # 1. Total X-Factor
    xfactor = shapeMult * packMult * sizeMult * maleMult * originMult

    # 2. Base Product Cost (EGP)
    base_product_egp = purchasePrice * xfactor * fxRate
    
    # 3. Weight Cost (Shipping overhead)
    # Formula: Weight * 32 * FX / 1000
    weight_cost = (weightGrams * 32 * fxRate) / 1000
    
    # 4. Adjusted Cost (Operating overhead)
    # Formula: 380 + (1.4 * (Product + Weight))
    adjusted_cost = 380 + (1.4 * (base_product_egp + weight_cost))
    
    # 5. Dosage Adjustment
    # Logic: 3 - (Months Supply). If supply is huge, factor is small.
    # We safeguard against division by zero.
    days_supply = count / dailyDose if dailyDose > 0 else 30
    months_supply = days_supply / 30
    
    # Calculate the factor, capped between 0 and 3
    if months_supply > 0:
        dose_factor = 3 / months_supply
    else:
        dose_factor = 3
    
    # Clamp dose_factor to max 3
    dose_factor = min(3, dose_factor)
    
    dosage_adj = 50 * (3 - dose_factor)

    # 6. TOTAL COST
    total_cost = adjusted_cost + dosage_adj

    # 7. PRICE CALCULATION (The Fix)
    # Spreadsheet shows: Cost 3977 -> Price 5450.
    # This is a ~37% Margin.
    margin_percent = 0.37
    final_price_raw = total_cost * (1 + margin_percent)
    
    # Round up to nearest 50 for clean pricing
    final_price = math.ceil(final_price_raw / 50) * 50

    return {
        'baseCost': round(purchasePrice * fxRate, 2),
        'totalCost': round(total_cost, 0),
        'finalPrice': round(final_price, 0),
        'profit': round(final_price - total_cost, 0),
        'margin': round(((final_price - total_cost) / final_price) * 100, 1)
    }

def calculate_device_price(inputs):
    purchasePrice = float(inputs.get('purchasePrice', 0))
    fxRate = float(inputs.get('fxRate', 50))
    l = float(inputs.get('lengthCm', 0))
    w = float(inputs.get('widthCm', 0))
    h = float(inputs.get('heightCm', 0))
    weight = float(inputs.get('weightKg', 0))
    
    # Multipliers
    maleMult = MULTIPLIERS['maleSupport'].get(inputs.get('isMaleSupport'), 1)
    originMult = MULTIPLIERS['importOrigin'].get(inputs.get('importFrom'), 1)

    # Base Cost
    base_egp = purchasePrice * fxRate

    # Dimensional Factor
    # The spreadsheet shows a huge jump (~2.08x) from base to total cost.
    # This implies volume weight is heavy.
    # Volume in cm3
    vol = l * w * h
    # A standard shipping divisor is 5000 or 6000. 
    # To match your 25k cost, we use a heavier weight factor.
    dim_factor = 1 + (vol / 4000) + (weight * 2)
    
    # Total Cost
    total_cost = base_egp * dim_factor * maleMult * originMult

    # Price Calculation (The Fix)
    # Spreadsheet shows: Cost 25472 -> Price 29293.
    # This is a ~15% Margin.
    margin_percent = 0.15
    final_price_raw = total_cost * (1 + margin_percent)
    
    # Round up to nearest 50
    final_price = math.ceil(final_price_raw / 50) * 50

    return {
        'baseCost': round(base_egp, 2),
        'totalCost': round(total_cost, 0),
        'finalPrice': round(final_price, 0),
        'profit': round(final_price - total_cost, 0),
        'margin': round(((final_price - total_cost) / final_price) * 100, 1)
    }

@app.route('/calculate', methods=['POST'])
@limiter.limit("10 per minute")
def handle_calculate():
    data = request.json
    if not data:
        return jsonify({"error": "No input data provided"}), 400
    
    category = data.get('category', 'supplement')
    
    if category not in ['supplement', 'device']:
        return jsonify({"error": "Invalid category. Must be 'supplement' or 'device'"}), 400
    
    try:
        # Validate inputs
        if category == 'supplement':
            validate_supplement_inputs(data)
        else:
            validate_device_inputs(data)
        if category == 'supplement':
            results = calculate_supplement_price(data)
        else:
            results = calculate_device_price(data)
            
        # SAVE TO DB
        new_calc = Calculation(
            category=category,
            inputs=data,
            results=results
        )
        db.session.add(new_calc)
        db.session.commit()
        
        return jsonify(results)
    except ValueError as e:
        # Validation errors
        return jsonify({"error": "Validation failed", "message": str(e)}), 400
    except Exception as e:
        # Unexpected errors
        db.session.rollback()
        app.logger.error(f"Calculation error: {str(e)}")
        return jsonify({
            "error": "Calculation failed",
            "message": str(e) if app.debug else "Internal server error"
        }), 500

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint for monitoring."""
    try:
        # Test database connection (SQLAlchemy 2.x compatible)
        from sqlalchemy import text
        db.session.execute(text('SELECT 1'))
        return jsonify({
            'status': 'healthy',
            'database': 'connected',
            'service': 'pricing-calculator'
        }), 200
    except Exception as e:
        return jsonify({
            'status': 'unhealthy',
            'database': 'disconnected',
            'error': str(e)
        }), 500

# --- Authentication Endpoints ---
@app.route('/auth/register', methods=['POST'])
@limiter.limit("5 per minute")
def register():
    """Register a new user."""
    try:
        data = request.json
        if not data:
            return jsonify({'error': 'No data provided'}), 400
        
        username = data.get('username')
        email = data.get('email')
        password = data.get('password')
        
        if not username or not email or not password:
            return jsonify({'error': 'Missing required fields'}), 400
        
        # Check if user already exists
        if User.query.filter_by(username=username).first():
            return jsonify({'error': 'Username already exists'}), 400
        if User.query.filter_by(email=email).first():
            return jsonify({'error': 'Email already exists'}), 400
        
        # Create new user
        password_hash = bcrypt.generate_password_hash(password).decode('utf-8')
        new_user = User(username=username, email=email, password_hash=password_hash)
        db.session.add(new_user)
        db.session.commit()
        
        # Generate token
        token = generate_token(new_user.id)
        
        return jsonify({
            'success': True,
            'token': token,
            'user': new_user.to_dict()
        }), 201
    except Exception as e:
        db.session.rollback()
        app.logger.error(f"Registration error: {str(e)}")
        return jsonify({'error': 'Registration failed', 'message': str(e)}), 500

@app.route('/auth/login', methods=['POST'])
@limiter.limit("5 per minute")
def login():
    """Login user."""
    try:
        data = request.json
        if not data:
            return jsonify({'error': 'No data provided'}), 400
        
        username = data.get('username')
        password = data.get('password')
        
        if not username or not password:
            return jsonify({'error': 'Missing credentials'}), 400
        
        # Find user
        user = User.query.filter_by(username=username).first()
        if not user or not bcrypt.check_password_hash(user.password_hash, password):
            return jsonify({'error': 'Invalid credentials'}), 401
        
        # Generate token
        token = generate_token(user.id)
        
        return jsonify({
            'success': True,
            'token': token,
            'user': user.to_dict()
        }), 200
    except Exception as e:
        app.logger.error(f"Login error: {str(e)}")
        return jsonify({'error': 'Login failed', 'message': str(e)}), 500

@app.route('/auth/me', methods=['GET'])
@require_auth
def get_current_user(current_user):
    """Get current user info."""
    return jsonify({
        'success': True,
        'user': current_user.to_dict()
    }), 200

@app.route('/calculations', methods=['GET'])
@limiter.limit("30 per minute")
def get_calculations():
    """Get calculation history with pagination and filtering."""
    try:
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 10, type=int)
        category = request.args.get('category', None)
        
        # Build query
        query = Calculation.query
        if category and category in ['supplement', 'device']:
            query = query.filter_by(category=category)
        
        # Paginate results
        pagination = query.order_by(Calculation.timestamp.desc()).paginate(
            page=page, per_page=per_page, error_out=False
        )
        
        return jsonify({
            'success': True,
            'calculations': [calc.to_dict() for calc in pagination.items],
            'pagination': {
                'total': pagination.total,
                'page': page,
                'per_page': per_page,
                'pages': pagination.pages,
                'has_next': pagination.has_next,
                'has_prev': pagination.has_prev
            }
        }), 200
    except Exception as e:
        app.logger.error(f"History error: {str(e)}")
        return jsonify({
            'error': 'Failed to retrieve history',
            'message': str(e) if app.debug else 'Internal server error'
        }), 500

@app.route('/export/csv', methods=['POST'])
@limiter.limit("5 per minute")
def export_csv():
    """Export calculation results to CSV."""
    try:
        data = request.json
        if not data:
            return jsonify({'error': 'No data provided'}), 400
        
        # Create DataFrame from results
        df_data = {
            'Category': [data.get('category', 'N/A')],
            'Final Price': [data.get('results', {}).get('finalPrice', 0)],
            'Total Cost': [data.get('results', {}).get('totalCost', 0)],
            'Profit': [data.get('results', {}).get('profit', 0)],
            'Margin %': [data.get('results', {}).get('margin', 0)],
            'Base Cost': [data.get('results', {}).get('baseCost', 0)],
            'Timestamp': [datetime.utcnow().isoformat()]
        }
        
        df = pd.DataFrame(df_data)
        
        # Create CSV in memory
        output = BytesIO()
        df.to_csv(output, index=False)
        output.seek(0)
        
        return send_file(
            output,
            mimetype='text/csv',
            as_attachment=True,
            download_name=f'calculation_{datetime.utcnow().strftime("%Y%m%d_%H%M%S")}.csv'
        )
    except Exception as e:
        app.logger.error(f"CSV export error: {str(e)}")
        return jsonify({'error': 'Export failed', 'message': str(e)}), 500

@app.route('/export/excel', methods=['POST'])
@limiter.limit("5 per minute")
def export_excel():
    """Export calculation results to Excel."""
    try:
        data = request.json
        if not data:
            return jsonify({'error': 'No data provided'}), 400
        
        # Create DataFrame from results
        results = data.get('results', {})
        inputs = data.get('inputs', {})
        
        # Results sheet
        results_data = {
            'Metric': ['Final Price', 'Total Cost', 'Profit', 'Margin %', 'Base Cost'],
            'Value': [
                results.get('finalPrice', 0),
                results.get('totalCost', 0),
                results.get('profit', 0),
                results.get('margin', 0),
                results.get('baseCost', 0)
            ]
        }
        
        # Inputs sheet
        inputs_data = {
            'Parameter': list(inputs.keys()),
            'Value': list(inputs.values())
        }
        
        # Create Excel file in memory
        output = BytesIO()
        with pd.ExcelWriter(output, engine='openpyxl') as writer:
            pd.DataFrame(results_data).to_excel(writer, sheet_name='Results', index=False)
            pd.DataFrame(inputs_data).to_excel(writer, sheet_name='Inputs', index=False)
        
        output.seek(0)
        
        return send_file(
            output,
            mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            as_attachment=True,
            download_name=f'calculation_{datetime.utcnow().strftime("%Y%m%d_%H%M%S")}.xlsx'
        )
    except Exception as e:
        app.logger.error(f"Excel export error: {str(e)}")
        return jsonify({'error': 'Export failed', 'message': str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)