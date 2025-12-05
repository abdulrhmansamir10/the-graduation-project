import { useState } from 'react';

// Inline SVG Icons - Enhanced versions
const CalculatorIcon = () => (
  <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 14h.01M12 14h.01M15 14h.01M12 17h.01M15 17h.01M12 20h.01M15 20h.01M9 20h.01M7 4h10a2 2 0 012 2v12a2 2 0 01-2 2H7a2 2 0 01-2-2V6a2 2 0 012-2z" />
  </svg>
);

const SupplementIcon = () => (
  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z" />
  </svg>
);

const DeviceIcon = () => (
  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
  </svg>
);

const MULTIPLIERS = {
  importOrigin: { US: 1, UK: 1.25, EU: 1.1 },
  productShape: { 'Capsules/Tablets': 1, 'Softgels/Chews': 1, 'Powder/Creamy': 1, 'Gummies': 1.1, 'Liquid': 1.05, 'Injection': 1.2 },
  bottleSize: { Small: 0.9, Normal: 1, Big: 1.1, Massive: 1.2 },
  packingMaterial: { Plastic: 1, Glass: 1.12, Paper: 1.06 }
};

// API_URL uses relative path - nginx proxies /api/* to backend container
const API_URL = '/api/calculate';

function App() {
  const [category, setCategory] = useState('supplement');
  const [results, setResults] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const [inputs, setInputs] = useState({
    purchasePrice: 44, fxRate: 50, count: 120, dailyDose: 2, weightGrams: 100,
    productShape: 'Capsules/Tablets', packingMaterial: 'Paper', bottleSize: 'Normal',
    isMaleSupport: 'No', importFrom: 'US', lengthCm: 10, widthCm: 45, heightCm: 20, weightKg: 0.3
  });

  const handle = (field, val) => setInputs(prev => ({ ...prev, [field]: val }));

  const calculate = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...inputs, category })
      });

      if (!res.ok) throw new Error('Calculation failed');

      const data = await res.json();
      setResults(data);
    } catch (e) {
      setError(e.message || "Error connecting to backend");
    }
    setLoading(false);
  };

  // Reusable Tailwind classes
  const container = "min-h-screen bg-[#1a1a1a] text-white p-6";
  const card = "bg-[#2a2a2a] rounded-lg border border-[#3a3a3a] p-6 shadow-lg";
  const input = "w-full px-3 py-2 bg-[#1a1a1a] border border-[#3a3a3a] rounded text-white focus:outline-none focus:border-blue-500 transition-colors";
  const label = "block text-sm font-medium mb-2 text-gray-300";
  const button = "w-full py-3 bg-blue-600 hover:bg-blue-700 disabled:bg-blue-800 disabled:cursor-not-allowed text-white font-semibold rounded transition-all transform active:scale-95";

  return (
    <div className={container}>
      <div className="max-w-4xl mx-auto">
        {/* Header */}
        <header className="flex items-center gap-3 mb-8">
          <CalculatorIcon />
          <div>
            <h1 className="text-3xl font-bold">EGV Pricing Calculator</h1>
            <p className="text-gray-400 text-sm mt-1">Cost & Margin Analyzer</p>
          </div>
        </header>

        {/* Tabs */}
        <div className="flex gap-2 mb-0">
          <button
            onClick={() => setCategory('supplement')}
            className={`flex items-center gap-2 px-4 py-2 rounded-t-lg font-medium transition-colors ${category === 'supplement'
              ? 'bg-[#2a2a2a] text-white border-t border-l border-r border-[#3a3a3a]'
              : 'bg-[#1a1a1a] text-gray-400 hover:text-white'
              }`}
          >
            <SupplementIcon />
            Supplement
          </button>
          <button
            onClick={() => setCategory('device')}
            className={`flex items-center gap-2 px-4 py-2 rounded-t-lg font-medium transition-colors ${category === 'device'
              ? 'bg-[#2a2a2a] text-white border-t border-l border-r border-[#3a3a3a]'
              : 'bg-[#1a1a1a] text-gray-400 hover:text-white'
              }`}
          >
            <DeviceIcon />
            Device
          </button>
        </div>

        {/* Form */}
        <div className={card}>
          {/* Global Settings */}
          <section className="mb-6">
            <h2 className="text-xl font-semibold mb-4 flex items-center gap-2">
              <span className="text-blue-500">•</span>
              Global Settings
            </h2>
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className={label}>Purchase Price ($)</label>
                <input type="number" value={inputs.purchasePrice} onChange={e => handle('purchasePrice', e.target.value)} className={input} step="0.01" />
              </div>
              <div>
                <label className={label}>FX Rate (EGP/$)</label>
                <input type="number" value={inputs.fxRate} onChange={e => handle('fxRate', e.target.value)} className={input} step="0.01" />
              </div>
              <div>
                <label className={label}>Import From</label>
                <select value={inputs.importFrom} onChange={e => handle('importFrom', e.target.value)} className={input}>
                  {Object.keys(MULTIPLIERS.importOrigin).map(o => <option key={o} value={o}>{o}</option>)}
                </select>
              </div>
              <div>
                <label className={label}>Male Support</label>
                <select value={inputs.isMaleSupport} onChange={e => handle('isMaleSupport', e.target.value)} className={input}>
                  <option value="No">No</option>
                  <option value="Yes">Yes</option>
                </select>
              </div>
            </div>
          </section>

          {/* Product Details */}
          <section className="mb-6">
            <h2 className="text-xl font-semibold mb-4 flex items-center gap-2">
              <span className="text-blue-500">•</span>
              {category === 'supplement' ? 'Supplement Details' : 'Device Dimensions'}
            </h2>

            {category === 'supplement' ? (
              <div className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className={label}>Count (Pills/Capsules)</label>
                    <input type="number" value={inputs.count} onChange={e => handle('count', e.target.value)} className={input} />
                  </div>
                  <div>
                    <label className={label}>Daily Dose</label>
                    <input type="number" value={inputs.dailyDose} onChange={e => handle('dailyDose', e.target.value)} className={input} />
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className={label}>Weight (grams)</label>
                    <input type="number" value={inputs.weightGrams} onChange={e => handle('weightGrams', e.target.value)} className={input} step="0.1" />
                  </div>
                  <div>
                    <label className={label}>Product Shape</label>
                    <select value={inputs.productShape} onChange={e => handle('productShape', e.target.value)} className={input}>
                      {Object.keys(MULTIPLIERS.productShape).map(s => <option key={s} value={s}>{s}</option>)}
                    </select>
                  </div>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className={label}>Packing Material</label>
                    <select value={inputs.packingMaterial} onChange={e => handle('packingMaterial', e.target.value)} className={input}>
                      {Object.keys(MULTIPLIERS.packingMaterial).map(s => <option key={s} value={s}>{s}</option>)}
                    </select>
                  </div>
                  <div>
                    <label className={label}>Bottle Size</label>
                    <select value={inputs.bottleSize} onChange={e => handle('bottleSize', e.target.value)} className={input}>
                      {Object.keys(MULTIPLIERS.bottleSize).map(s => <option key={s} value={s}>{s}</option>)}
                    </select>
                  </div>
                </div>
              </div>
            ) : (
              <div className="space-y-4">
                <div className="grid grid-cols-3 gap-4">
                  <div>
                    <label className={label}>Length (cm)</label>
                    <input type="number" value={inputs.lengthCm} onChange={e => handle('lengthCm', e.target.value)} className={input} step="0.1" />
                  </div>
                  <div>
                    <label className={label}>Width (cm)</label>
                    <input type="number" value={inputs.widthCm} onChange={e => handle('widthCm', e.target.value)} className={input} step="0.1" />
                  </div>
                  <div>
                    <label className={label}>Height (cm)</label>
                    <input type="number" value={inputs.heightCm} onChange={e => handle('heightCm', e.target.value)} className={input} step="0.1" />
                  </div>
                </div>
                <div>
                  <label className={label}>Weight (kg)</label>
                  <input type="number" value={inputs.weightKg} onChange={e => handle('weightKg', e.target.value)} className={input} step="0.01" />
                </div>
              </div>
            )}
          </section>

          <button onClick={calculate} className={button} disabled={loading}>
            {loading ? 'Calculating...' : 'Calculate Price'}
          </button>

          {error && (
            <div className="mt-4 p-4 bg-red-900/50 border border-red-700 rounded text-red-100">
              <strong>Error:</strong> {error}
            </div>
          )}

          {/* Results */}
          {results && !loading && (
            <section className="mt-6 pt-6 border-t border-[#3a3a3a]">
              <h2 className="text-xl font-semibold mb-4 flex items-center gap-2">
                <span className="text-blue-500">•</span>
                Calculation Results
              </h2>

              <div className="bg-gradient-to-br from-blue-600 to-blue-800 rounded-lg p-6 mb-4 text-center">
                <div className="text-sm text-blue-100 uppercase tracking-wider mb-2">Final Sales Price</div>
                <div className="text-5xl font-bold text-white">
                  EGP {results.finalPrice?.toLocaleString() || '0'}
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div className="bg-[#1a1a1a] rounded border border-[#3a3a3a] p-4">
                  <div className="text-sm text-gray-400 mb-1">Total Cost</div>
                  <div className="text-2xl font-bold">EGP {results.totalCost?.toLocaleString()}</div>
                </div>
                <div className="bg-[#1a1a1a] rounded border border-[#3a3a3a] p-4">
                  <div className="text-sm text-gray-400 mb-1">Profit</div>
                  <div className="text-2xl font-bold text-green-400">+EGP {results.profit?.toLocaleString()}</div>
                </div>
                <div className="bg-[#1a1a1a] rounded border border-[#3a3a3a] p-4">
                  <div className="text-sm text-gray-400 mb-1">Margin</div>
                  <div className="text-2xl font-bold text-blue-400">{results.margin}%</div>
                </div>
                <div className="bg-[#1a1a1a] rounded border border-[#3a3a3a] p-4">
                  <div className="text-sm text-gray-400 mb-1">Base Cost</div>
                  <div className="text-2xl font-bold">EGP {results.baseCost?.toLocaleString()}</div>
                </div>
              </div>
            </section>
          )}
        </div>
      </div>
    </div>
  );
}

export default App;