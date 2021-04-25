/**
 * @file
 * Implements Bands strategy based on the Bollinger Bands indicator.
 */

// User input params.
INPUT string __Bands_Parameters__ = "-- Bands strategy params --";  // >>> BANDS <<<
INPUT float Bands_LotSize = 0;                                      // Lot size
INPUT int Bands_SignalOpenMethod = 0;                               // Signal open method (-63-63)
INPUT float Bands_SignalOpenLevel = 0.0f;                           // Signal open level (-49-49)
INPUT int Bands_SignalOpenFilterMethod = 1;                         // Signal open filter method (-49-49)
INPUT int Bands_SignalOpenBoostMethod = 0;                          // Signal open boost method (-49-49)
INPUT int Bands_SignalCloseMethod = 0;                              // Signal close method (-63-63)
INPUT float Bands_SignalCloseLevel = 0.0f;                          // Signal close level (-49-49)
INPUT int Bands_PriceStopMethod = 0;                                // Price stop method (0-6)
INPUT float Bands_PriceStopLevel = 10;                              // Price stop level
INPUT int Bands_TickFilterMethod = 1;                               // Tick filter method
INPUT float Bands_MaxSpread = 4.0;                                  // Max spread to trade (pips)
INPUT short Bands_Shift = 0;                                        // Shift (relative to the current bar, 0 - default)
INPUT int Bands_OrderCloseTime = -20;                               // Order close time in mins (>0) or bars (<0)
INPUT string __Bands_Indi_Bands_Parameters__ =
    "-- Bands strategy: Bands indicator params --";                     // >>> Bands strategy: Bands indicator <<<
INPUT int Bands_Indi_Bands_Period = 2;                                  // Period
INPUT float Bands_Indi_Bands_Deviation = 0.3f;                          // Deviation
INPUT int Bands_Indi_Bands_HShift = 0;                                  // Horizontal shift
INPUT ENUM_APPLIED_PRICE Bands_Indi_Bands_Applied_Price = PRICE_CLOSE;  // Applied Price
INPUT int Bands_Indi_Bands_Shift = 0;                                   // Shift

// Structs.

// Defines struct with default user indicator values.
struct Indi_Bands_Params_Defaults : BandsParams {
  Indi_Bands_Params_Defaults()
      : BandsParams(::Bands_Indi_Bands_Period, ::Bands_Indi_Bands_Deviation, ::Bands_Indi_Bands_HShift,
                    ::Bands_Indi_Bands_Applied_Price, ::Bands_Indi_Bands_Shift) {}
} indi_bands_defaults;

// Defines struct with default user strategy values.
struct Stg_Bands_Params_Defaults : StgParams {
  Stg_Bands_Params_Defaults()
      : StgParams(::Bands_SignalOpenMethod, ::Bands_SignalOpenFilterMethod, ::Bands_SignalOpenLevel,
                  ::Bands_SignalOpenBoostMethod, ::Bands_SignalCloseMethod, ::Bands_SignalCloseLevel,
                  ::Bands_PriceStopMethod, ::Bands_PriceStopLevel, ::Bands_TickFilterMethod, ::Bands_MaxSpread,
                  ::Bands_Shift, ::Bands_OrderCloseTime) {}
} stg_bands_defaults;

// Struct to define strategy parameters to override.
struct Stg_Bands_Params : StgParams {
  BandsParams iparams;
  StgParams sparams;

  // Struct constructors.
  Stg_Bands_Params(BandsParams &_iparams, StgParams &_sparams)
      : iparams(indi_bands_defaults, _iparams.tf), sparams(stg_bands_defaults) {
    iparams = _iparams;
    sparams = _sparams;
  }
};

// Loads pair specific param values.
#include "config/EURUSD_H1.h"
#include "config/EURUSD_H4.h"
#include "config/EURUSD_H8.h"
#include "config/EURUSD_M1.h"
#include "config/EURUSD_M15.h"
#include "config/EURUSD_M30.h"
#include "config/EURUSD_M5.h"

class Stg_Bands : public Strategy {
 public:
  Stg_Bands(StgParams &_sparams, TradeParams &_tparams, ChartParams &_cparams, string _name = "")
      : Strategy(_sparams, _tparams, _cparams, _name) {}

  static Stg_Bands *Init(ENUM_TIMEFRAMES _tf = NULL, long _magic_no = NULL, ENUM_LOG_LEVEL _log_level = V_INFO) {
    // Initialize strategy initial values.
    BandsParams _indi_params(indi_bands_defaults, _tf);
    StgParams _stg_params(stg_bands_defaults);
#ifdef __config__
    SetParamsByTf<BandsParams>(_indi_params, _tf, indi_bands_m1, indi_bands_m5, indi_bands_m15, indi_bands_m30,
                               indi_bands_h1, indi_bands_h4, indi_bands_h8);
    SetParamsByTf<StgParams>(_stg_params, _tf, stg_bands_m1, stg_bands_m5, stg_bands_m15, stg_bands_m30, stg_bands_h1,
                             stg_bands_h4, stg_bands_h8);
#endif
    // Initialize indicator.
    BandsParams bands_params(_indi_params);
    _stg_params.SetIndicator(new Indi_Bands(_indi_params));
    // Initialize Strategy instance.
    ChartParams _cparams(_tf, _Symbol);
    TradeParams _tparams(_magic_no, _log_level);
    Strategy *_strat = new Stg_Bands(_stg_params, _tparams, _cparams, "Bands");
    return _strat;
  }

  /**
   * Check strategy's opening signal.
   */
  bool SignalOpen(ENUM_ORDER_TYPE _cmd, int _method = 0, float _level = 0.0f, int _shift = 0) {
    Chart *_chart = trade.GetChart();
    Indi_Bands *_indi = GetIndicator();
    bool _is_valid = _indi[CURR].IsValid() && _indi[PREV].IsValid() && _indi[PPREV].IsValid();
    bool _result = _is_valid;
    if (_is_valid) {
      double _change_pc = Math::ChangeInPct(_indi[1][(int)BAND_BASE], _indi[0][(int)BAND_BASE], true);
      switch (_cmd) {
        // Buy: price crossed lower line upwards (returned to it from below).
        case ORDER_TYPE_BUY: {
          // Price value was lower than the lower band.
          double lowest_price = fmin3(_chart.GetLow(CURR), _chart.GetLow(PREV), _chart.GetLow(PPREV));
          _result = (lowest_price <
                     fmax3(_indi[CURR][(int)BAND_LOWER], _indi[PREV][(int)BAND_LOWER], _indi[PPREV][(int)BAND_LOWER]));
          _result &= _change_pc > _level;
          if (_result && _method != 0) {
            if (METHOD(_method, 0)) _result &= fmin(Close[PREV], Close[PPREV]) < _indi[CURR][(int)BAND_LOWER];
            if (METHOD(_method, 1)) _result &= (_indi[CURR][(int)BAND_LOWER] > _indi[PPREV][(int)BAND_LOWER]);
            if (METHOD(_method, 2)) _result &= (_indi[CURR][(int)BAND_BASE] > _indi[PPREV][(int)BAND_BASE]);
            if (METHOD(_method, 3)) _result &= (_indi[CURR][(int)BAND_UPPER] > _indi[PPREV][(int)BAND_UPPER]);
            if (METHOD(_method, 4)) _result &= lowest_price < _indi[CURR][(int)BAND_BASE];
            if (METHOD(_method, 5)) _result &= Open[CURR] < _indi[CURR][(int)BAND_BASE];
            if (METHOD(_method, 6)) _result &= fmin(Close[PREV], Close[PPREV]) > _indi[CURR][(int)BAND_BASE];
          }
          break;
        }
        // Sell: price crossed upper line downwards (returned to it from above).
        case ORDER_TYPE_SELL: {
          // Price value was higher than the upper band.
          double highest_price = fmin3(_chart.GetHigh(CURR), _chart.GetHigh(PREV), _chart.GetHigh(PPREV));
          _result = (highest_price >
                     fmin3(_indi[CURR][(int)BAND_UPPER], _indi[PREV][(int)BAND_UPPER], _indi[PPREV][(int)BAND_UPPER]));
          _result &= _change_pc < _level;
          if (_result && _method != 0) {
            if (METHOD(_method, 0)) _result &= fmin(Close[PREV], Close[PPREV]) > _indi[CURR][(int)BAND_UPPER];
            if (METHOD(_method, 1)) _result &= (_indi[CURR][(int)BAND_LOWER] < _indi[PPREV][(int)BAND_LOWER]);
            if (METHOD(_method, 2)) _result &= (_indi[CURR][(int)BAND_BASE] < _indi[PPREV][(int)BAND_BASE]);
            if (METHOD(_method, 3)) _result &= (_indi[CURR][(int)BAND_UPPER] < _indi[PPREV][(int)BAND_UPPER]);
            if (METHOD(_method, 4)) _result &= highest_price > _indi[CURR][(int)BAND_BASE];
            if (METHOD(_method, 5)) _result &= Open[CURR] > _indi[CURR][(int)BAND_BASE];
            if (METHOD(_method, 6)) _result &= fmin(Close[PREV], Close[PPREV]) < _indi[CURR][(int)BAND_BASE];
          }
          break;
        }
      }
    }
    return _result;
  }

  /**
   * Gets price stop value for profit take or stop loss.
   */
  float PriceStop(ENUM_ORDER_TYPE _cmd, ENUM_ORDER_TYPE_VALUE _mode, int _method = 0, float _level = 0.0) {
    Indi_Bands *_indi = GetIndicator();
    Chart *_chart = trade.GetChart();
    double _trail = _level * _chart.GetPipSize();
    int _direction = Order::OrderDirection(_cmd, _mode);
    double _change_pc = Math::ChangeInPct(_indi[1][(int)BAND_BASE], _indi[0][(int)BAND_BASE]);
    double _default_value = _chart.GetCloseOffer(_cmd) + _trail * _method * _direction;
    double _price_offer = _chart.GetOpenOffer(_cmd);
    double _result = _default_value;
    ENUM_APPLIED_PRICE _ap = _direction > 0 ? PRICE_HIGH : PRICE_LOW;
    switch (_method) {
      case 1:
        _result = (_direction > 0 ? _indi[CURR][(int)BAND_UPPER] : _indi[CURR][(int)BAND_LOWER]) + _trail * _direction;
        break;
      case 2:
        _result = (_direction > 0 ? _indi[PREV][(int)BAND_UPPER] : _indi[PREV][(int)BAND_LOWER]) + _trail * _direction;
        break;
      case 3:
        _result =
            (_direction > 0 ? _indi[PPREV][(int)BAND_UPPER] : _indi[PPREV][(int)BAND_LOWER]) + _trail * _direction;
        break;
      case 4:
        _result = (_direction > 0 ? fmax(_indi[PREV][(int)BAND_UPPER], _indi[PPREV][(int)BAND_UPPER])
                                  : fmin(_indi[PREV][(int)BAND_LOWER], _indi[PPREV][(int)BAND_LOWER])) +
                  _trail * _direction;
        break;
      case 5:
        _result = _indi[CURR][(int)BAND_BASE] + _trail * _direction;
        break;
      case 6:
        _result = _indi[PREV][(int)BAND_BASE] + _trail * _direction;
        break;
      case 7:
        _result = _indi[PPREV][(int)BAND_BASE] + _trail * _direction;
        break;
      case 8: {
        int _bar_count = (int)_level * (int)_indi.GetPeriod();
        _result = _direction > 0 ? _indi.GetPrice(PRICE_HIGH, _indi.GetHighest<double>(_bar_count))
                                 : _indi.GetPrice(PRICE_LOW, _indi.GetLowest<double>(_bar_count));
        break;
      }
      case 9:
        _result = Math::ChangeByPct(_price_offer, (float)(_change_pc / Math::NonZero(_level)));
        break;
    }
    return (float)_result;
  }
};
