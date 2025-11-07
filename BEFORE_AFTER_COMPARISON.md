# Before vs After - Concrete Examples

## Example Scenario: New API Endpoint

**Code Change:**
```ruby
# app/controllers/payments_controller.rb
class PaymentsController < ApplicationController
  def create
    payment = PaymentService.process(params[:amount])
    
    if payment.success?
      logger.info "Payment processed: #{payment.id}"
      render json: payment, status: :created
    else
      logger.error "Payment failed: #{payment.error_message}"
      render json: { error: payment.error_message }, status: :unprocessable_entity
    end
  rescue PaymentGatewayTimeout => e
    logger.warn "Payment gateway timeout: #{e.message}"
    render json: { error: "Service temporarily unavailable" }, status: :service_unavailable
  end
end
```

---

## BEFORE (Old Version)

### Trigger:
- Every PR open/sync → Runs even on trivial PRs
- Can't re-run without closing/reopening PR

### Analysis Output:
```markdown
## Analysis

This PR adds a new payment endpoint.

### Suggested Monitoring

Dashboard:
- Request count
- Error rate

Alerts:
- High error rate (>10%)

Add these to infrastructure.yml and monitor during rollout.
```

**Problems:**
1. ❌ Only 1-2 recommendations
2. ❌ No log monitoring
3. ❌ Generic thresholds (10%)
4. ❌ No dependency analysis
5. ❌ appName might be wrong
6. ❌ Missing detailed breakdown

---

## AFTER (Enhanced Version)

### Trigger:
- Comment "Constant Vigilance" → Runs only when needed
- Can re-run unlimited times
- Reacts with 👀 to confirm

### Analysis Output:
```markdown
## 🔍 Analysis Summary

This PR adds a new payment processing endpoint with external payment gateway integration. 
Critical user-facing change requiring comprehensive monitoring for financial transactions and timeout handling.

## 📋 Scope of Changes Analyzed

- **API Endpoints**: 1 endpoint (PaymentsController#create)
- **Database Queries**: 2 queries (payment creation, user lookup)
- **Background Jobs**: 0 jobs
- **External APIs**: 1 integration (PaymentGateway)
- **Log Statements**: 1 error log, 1 warning log, 1 info log
- **Classes Modified**: 1 (PaymentsController) with 3 method dependencies

## 🎯 Dependency Impact Assessment

**Impact Level**: Medium-High
**References Found**: 12 code references to PaymentService
**Monitoring Priority**: P1 - Should have monitoring before merge

Details:
- UserCheckoutController calls PaymentService.process
- SubscriptionController uses same payment flow
- RefundWorker depends on payment success states
- **Risk**: Payment failures will cascade to checkout and subscriptions

## 📊 Baseline Metrics (from last 7 days)

- Current Error Rate: 2.3%
- Average Throughput: 450 req/min
- P95 Latency: 285ms
- Payment Gateway P95: 520ms
- Baseline used for alert thresholds

## 📈 Permanent Observability Configuration

### Dashboard: Payment Processing Monitor

Add to `infrastructure.yml`:

```yaml
newrelicDashboards:
  - name: Payment Processing Dashboard
    oneDashboardConfig:
      pages:
        - name: Payment Health
          description: Real-time payment processing monitoring
          widgets:
            # Golden Signals
            - visualization: "billboard"
              dataSource:
                nrql: |
                  SELECT count(*) as 'Total Payments'
                  FROM Transaction
                  WHERE appName = 'syncsoldier-production'
                    AND name = 'Controller/payments/create'
                  SINCE 1 hour ago
            
            - visualization: "billboard"
              dataSource:
                nrql: |
                  SELECT percentage(count(*), WHERE httpResponseCode < 400) as 'Success Rate'
                  FROM Transaction
                  WHERE appName = 'syncsoldier-production'
                    AND name = 'Controller/payments/create'
                  SINCE 1 hour ago
            
            - visualization: "billboard"
              dataSource:
                nrql: |
                  SELECT percentage(count(*), WHERE httpResponseCode >= 500) as '5xx Rate'
                  FROM Transaction
                  WHERE appName = 'syncsoldier-production'
                    AND name = 'Controller/payments/create'
                  SINCE 1 hour ago
            
            - visualization: "metric_line_chart"
              dataSource:
                nrql: |
                  SELECT count(*) as 'Request Rate'
                  FROM Transaction
                  WHERE appName = 'syncsoldier-production'
                    AND name = 'Controller/payments/create'
                  SINCE 1 hour ago
                  TIMESERIES
            
            # Performance Monitoring
            - visualization: "metric_line_chart"
              dataSource:
                nrql: |
                  SELECT percentile(duration, 50, 95, 99) 
                  FROM Transaction
                  WHERE appName = 'syncsoldier-production'
                    AND name = 'Controller/payments/create'
                  SINCE 1 hour ago
                  TIMESERIES
            
            - visualization: "billboard"
              dataSource:
                nrql: |
                  SELECT count(*) as 'Slow Requests'
                  FROM Transaction
                  WHERE appName = 'syncsoldier-production'
                    AND name = 'Controller/payments/create'
                    AND duration > 1
                  SINCE 1 hour ago
            
            # Error Analysis
            - visualization: "facet_table"
              dataSource:
                nrql: |
                  SELECT count(*), average(duration), percentage(count(*), WHERE httpResponseCode >= 400) as 'Error %'
                  FROM Transaction
                  WHERE appName = 'syncsoldier-production'
                    AND name LIKE 'Controller/payments%'
                  FACET name
                  SINCE 1 hour ago
            
            - visualization: "pie_chart"
              dataSource:
                nrql: |
                  SELECT count(*)
                  FROM Transaction
                  WHERE appName = 'syncsoldier-production'
                    AND name = 'Controller/payments/create'
                  FACET httpResponseCode
                  SINCE 1 hour ago
            
            # External Service Monitoring
            - visualization: "metric_line_chart"
              dataSource:
                nrql: |
                  SELECT average(duration) as 'Gateway Response Time'
                  FROM Transaction
                  WHERE appName = 'syncsoldier-production'
                    AND name LIKE '%PaymentGateway%'
                  SINCE 1 hour ago
                  TIMESERIES
            
            - visualization: "billboard"
              dataSource:
                nrql: |
                  SELECT count(*) as 'Gateway Timeouts'
                  FROM Transaction
                  WHERE appName = 'syncsoldier-production'
                    AND name LIKE '%PaymentGateway%'
                    AND error IS true
                    AND error.message LIKE '%timeout%'
                  SINCE 1 hour ago
            
            # Log-Based Monitoring
            - visualization: "metric_line_chart"
              dataSource:
                nrql: |
                  SELECT count(*)
                  FROM Log
                  WHERE message LIKE '%Payment failed%'
                    AND level = 'error'
                  SINCE 1 hour ago
                  TIMESERIES
            
            - visualization: "facet_table"
              dataSource:
                nrql: |
                  SELECT count(*), latest(message)
                  FROM Log
                  WHERE (message LIKE '%Payment%' OR message LIKE '%payment%')
                    AND level IN ('error', 'warn')
                  FACET level, message
                  SINCE 1 hour ago
                  LIMIT 20
```

### Alerts: Payment Processing

Add to `infrastructure.yml`:

```yaml
newrelic:
  - name: Payment Processing Policy
    entityName: syncsoldier-production
    entityDomain: APM
    incidentPreference: PER_CONDITION
    alertNotificationChannels: ["default"]
    nrqlAlertConditions:
      # Alert 1: High Error Rate
      - name: "High Payment Error Rate"
        description: "Triggers when payment errors exceed acceptable thresholds (baseline: 2.3%)"
        type: static
        enabled: true
        valueFunction: single_value
        aggregationMethod: EVENT_FLOW
        aggregationDelay: 20
        aggregationWindow: 60
        fillOption: NONE
        violationTimeLimitSeconds: 1800
        nrql:
          query: |
            SELECT percentage(count(*), WHERE httpResponseCode >= 400)
            FROM Transaction
            WHERE appName = 'syncsoldier-production'
              AND name = 'Controller/payments/create'
        warning:
          operator: above
          threshold: 5
          thresholdDuration: 300
          thresholdOccurrences: ALL
        critical:
          operator: above
          threshold: 10
          thresholdDuration: 300
          thresholdOccurrences: ALL
      
      # Alert 2: Slow Payment Processing
      - name: "Slow Payment Processing"
        description: "Triggers when payment processing is slower than baseline (baseline p95: 285ms)"
        type: static
        enabled: true
        valueFunction: single_value
        aggregationMethod: EVENT_FLOW
        aggregationDelay: 20
        aggregationWindow: 300
        fillOption: NONE
        violationTimeLimitSeconds: 7200
        nrql:
          query: |
            SELECT percentile(duration, 95)
            FROM Transaction
            WHERE appName = 'syncsoldier-production'
              AND name = 'Controller/payments/create'
        warning:
          operator: above
          threshold: 570
          thresholdDuration: 300
          thresholdOccurrences: ALL
        critical:
          operator: above
          threshold: 855
          thresholdDuration: 300
          thresholdOccurrences: ALL
      
      # Alert 3: Payment Gateway Timeout
      - name: "Payment Gateway Timeout Rate"
        description: "Triggers when payment gateway timeouts exceed thresholds"
        type: static
        enabled: true
        valueFunction: single_value
        aggregationMethod: EVENT_FLOW
        aggregationDelay: 20
        aggregationWindow: 300
        fillOption: NONE
        violationTimeLimitSeconds: 1800
        nrql:
          query: |
            SELECT percentage(count(*), WHERE httpResponseCode = 503)
            FROM Transaction
            WHERE appName = 'syncsoldier-production'
              AND name = 'Controller/payments/create'
        warning:
          operator: above
          threshold: 1
          thresholdDuration: 300
          thresholdOccurrences: ALL
        critical:
          operator: above
          threshold: 5
          thresholdDuration: 300
          thresholdOccurrences: ALL
      
      # Alert 4: Error Log - Payment Failed
      - name: "Error Log: Payment Failed"
        description: "Triggers when payment failure errors occur in logs"
        type: static
        enabled: true
        valueFunction: single_value
        aggregationMethod: EVENT_FLOW
        aggregationDelay: 20
        aggregationWindow: 60
        fillOption: NONE
        violationTimeLimitSeconds: 1800
        nrql:
          query: |
            SELECT count(*)
            FROM Log
            WHERE message LIKE '%Payment failed%'
              AND level = 'error'
        warning:
          operator: above
          threshold: 10
          thresholdDuration: 300
          thresholdOccurrences: ALL
        critical:
          operator: above
          threshold: 50
          thresholdDuration: 300
          thresholdOccurrences: ALL
      
      # Alert 5: Warning Log - Gateway Timeout
      - name: "Warning Log: Payment Gateway Timeout"
        description: "Triggers when gateway timeout warnings occur in logs"
        type: static
        enabled: true
        valueFunction: single_value
        aggregationMethod: EVENT_FLOW
        aggregationDelay: 20
        aggregationWindow: 60
        fillOption: NONE
        violationTimeLimitSeconds: 1800
        nrql:
          query: |
            SELECT count(*)
            FROM Log
            WHERE message LIKE '%Payment gateway timeout%'
              AND level = 'warn'
        warning:
          operator: above
          threshold: 20
          thresholdDuration: 300
          thresholdOccurrences: ALL
        critical:
          operator: above
          threshold: 100
          thresholdDuration: 300
          thresholdOccurrences: ALL
      
      # Alert 6: Cascade Impact - Checkout Failures
      - name: "Cascade Failure: Checkout Impact"
        description: "Monitors downstream checkout errors that may be caused by payment issues"
        type: static
        enabled: true
        valueFunction: single_value
        aggregationMethod: EVENT_FLOW
        aggregationDelay: 20
        aggregationWindow: 300
        fillOption: NONE
        violationTimeLimitSeconds: 7200
        nrql:
          query: |
            SELECT percentage(count(*), WHERE error IS true)
            FROM Transaction
            WHERE appName = 'syncsoldier-production'
              AND name LIKE '%checkout%'
        warning:
          operator: above
          threshold: 7
          thresholdDuration: 300
          thresholdOccurrences: ALL
        critical:
          operator: above
          threshold: 15
          thresholdDuration: 300
          thresholdOccurrences: ALL
```

## 🚀 Next Steps

1. **Immediate**: Review and add dashboard config to infrastructure.yml
2. **High Priority**: Add all 6 alert conditions (especially error and timeout alerts)
3. **Verify**: Test payment flow in staging and confirm all metrics populate
4. **Monitor**: Watch dashboard during first production deployment
5. **Tune**: Adjust alert thresholds after 48 hours of real traffic
6. **Document**: Add runbook links for what to do when alerts fire

## 📝 Dependency Impact Notes

**Critical Dependencies Found:**
- UserCheckoutController → Monitor checkout success rate
- SubscriptionController → Monitor subscription creation rate
- RefundWorker → Monitor refund processing

**Recommended Additional Monitoring:**
- Add end-to-end success rate tracking (signup → payment → activation)
- Set up correlation dashboard showing payment vs checkout trends
- Consider SLO alert for critical user journey

---

💡 **Pro Tip**: This comprehensive monitoring will catch issues like:
- Payment gateway degradation before it becomes critical
- Timeout patterns that indicate capacity problems
- Cascade failures affecting user signup flow
- Log-based early warning of payment processor issues
```

---

## Key Improvements Summary

| Aspect | Before | After |
|--------|--------|-------|
| **Recommendations** | 1-2 items | 12+ items (6 alerts + 12 widgets) |
| **Log Monitoring** | ❌ None | ✅ All error/warn logs covered |
| **Dependency Analysis** | ❌ None | ✅ 12 references found, impact assessed |
| **Baseline Metrics** | ❌ Generic thresholds | ✅ Based on actual 7-day data |
| **appName Accuracy** | ❌ Might be wrong | ✅ Auto-detected from NewRelic |
| **Dashboard Widgets** | 2 | 12 (comprehensive coverage) |
| **Alert Coverage** | Error rate only | All failure modes + logs + cascade |
| **Visualization Types** | Generic | Specific (billboard, line_chart, facet_table, etc.) |
| **Trigger Control** | Every PR | On-demand with comment |

**Bottom Line:**
- **Before**: Minimal monitoring, might miss issues
- **After**: Production-grade monitoring, catches issues before incidents

---

## Cost Impact

**Before:**
- Runs on every PR: ~20 PRs/week
- Cost: 20 × $0.10 = **$2/week** ($8/month)

**After:**
- Runs on-demand: ~5 PRs/week need analysis
- Cost: 5 × $0.20 = **$1/week** ($4/month)

**Net savings: ~50%** despite more thorough analysis!
