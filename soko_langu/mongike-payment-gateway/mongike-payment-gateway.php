<?php
/**
 * Plugin Name: Mongike Payment Gateway (Advanced)
 * Description: Tanzania Mobile Money via Mongike API with Debug Logs
 * Version: 3.0.0
 * Author: Mongike
 */

if ( ! defined( 'ABSPATH' ) ) exit;

/**
 * ============================
 * 🔥 LOGGING SYSTEM
 * ============================
 */

function mongike_log( $message ) {
    global $wpdb;

    $table = $wpdb->prefix . 'mongike_logs';

    $wpdb->insert($table, [
        'log' => maybe_serialize($message),
        'created_at' => current_time('mysql')
    ]);
}

/**
 * Create logs table
 */
register_activation_hook(__FILE__, function () {
    global $wpdb;

    $table = $wpdb->prefix . 'mongike_logs';
    $charset_collate = $wpdb->get_charset_collate();

    $sql = "CREATE TABLE $table (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        log LONGTEXT,
        created_at DATETIME
    ) $charset_collate;";

    require_once(ABSPATH . 'wp-admin/includes/upgrade.php');
    dbDelta($sql);
});

/**
 * ============================
 * 🔥 WEBHOOK (GLOBAL)
 * ============================
 */

add_action('rest_api_init', function () {

    register_rest_route('mongike/v1', '/webhook', [
        'methods'  => 'POST',
        'callback' => 'mongike_webhook_handler',
        'permission_callback' => '__return_true',
    ]);

});

function mongike_webhook_handler($request) {

    $data = $request->get_json_params();

    mongike_log(['WEBHOOK_RECEIVED' => $data]);

    if (empty($data)) {
        return new WP_REST_Response(['message'=>'No data'], 400);
    }

    $order_key = $data['order_id'] ?? '';

    if (!$order_key) {
        return new WP_REST_Response(['message'=>'Missing order_id'], 400);
    }

    if (!function_exists('wc_get_order_id_by_order_key')) {
        mongike_log('WooCommerce not loaded');
        return new WP_REST_Response(['message'=>'WC not loaded'], 500);
    }

    $order_id = wc_get_order_id_by_order_key($order_key);
    $order = $order_id ? wc_get_order($order_id) : null;

    if (!$order) {
        mongike_log('Order not found: '.$order_key);
        return new WP_REST_Response(['message'=>'Order not found'], 404);
    }

    $status = strtoupper($data['payment_status'] ?? '');

    if ($status === 'COMPLETED') {

        $order->payment_complete($data['reference'] ?? '');
        $order->add_order_note('Mongike Payment SUCCESS');

        mongike_log(['PAYMENT_SUCCESS'=>$order_id]);

    } else {

        $order->update_status('failed', 'Payment failed');
        mongike_log(['PAYMENT_FAILED'=>$order_id]);

    }

    return new WP_REST_Response(['message'=>'OK'], 200);
}

/**
 * ============================
 * 🔥 WOOCOMMERCE GATEWAY
 * ============================
 */

add_action('plugins_loaded', function () {

    if (!class_exists('WooCommerce')) return;
    if (!class_exists('WC_Payment_Gateway')) return;

    class WC_Gateway_Mongike extends WC_Payment_Gateway {

        public function __construct() {

            $this->id = 'mongike';
            $this->method_title = 'Mongike Mobile Money';
            $this->has_fields = true;

            $this->init_form_fields();
            $this->init_settings();

            $this->title = $this->get_option('title');
            $this->api_key = $this->get_option('api_key');
            $this->api_url = $this->get_option('api_url');

            add_action(
                'woocommerce_update_options_payment_gateways_'.$this->id,
                [$this,'process_admin_options']
            );
        }

        public function init_form_fields() {

            $this->form_fields = [

                'enabled' => [
                    'title'=>'Enable',
                    'type'=>'checkbox',
                    'default'=>'yes'
                ],

                'title' => [
                    'title'=>'Title',
                    'type'=>'text',
                    'default'=>'Mobile Money (TZ)'
                ],

                'api_url' => [
                    'title'=>'API URL',
                    'type'=>'text',
                    'default'=>'https://mongike.com/api/v1'
                ],

                'api_key' => [
                    'title'=>'API Key',
                    'type'=>'text'
                ],
            ];
        }

        public function payment_fields() {

            echo '<input type="tel" name="mongike_phone" placeholder="2557XXXXXXXX" required />';
        }

        public function process_payment($order_id) {

            $order = wc_get_order($order_id);
            $phone = sanitize_text_field($_POST['mongike_phone']);

            if (!preg_match('/^255[67]\d{8}$/', $phone)) {
                wc_add_notice('Invalid phone', 'error');
                return;
            }

            $payload = [
                'order_id' => $order->get_order_key(),
                'amount' => (float)$order->get_total(),
                'buyer_phone' => $phone,
                'webhook_url' => home_url('/wp-json/mongike/v1/webhook')
            ];

            mongike_log(['PAYMENT_REQUEST'=>$payload]);

            $response = wp_remote_post($this->api_url.'/payments/mobile-money/tanzania', [
                'headers'=>[
                    'x-api-key'=>$this->api_key,
                    'Content-Type'=>'application/json'
                ],
                'body'=>json_encode($payload)
            ]);

            if (is_wp_error($response)) {
                mongike_log($response->get_error_message());
                wc_add_notice('API Error','error');
                return;
            }

            $order->update_status('on-hold','Waiting payment');

            return [
                'result'=>'success',
                'redirect'=>$this->get_return_url($order)
            ];
        }
    }

    add_filter('woocommerce_payment_gateways', function ($methods) {
        $methods[] = 'WC_Gateway_Mongike';
        return $methods;
    });

});

/**
 * ============================
 * 🔥 ADMIN LOG VIEWER
 * ============================
 */

add_action('admin_menu', function () {

    add_submenu_page(
        'woocommerce',
        'Mongike Logs',
        'Mongike Logs',
        'manage_options',
        'mongike-logs',
        'mongike_logs_page'
    );
});

function mongike_logs_page() {

    global $wpdb;
    $table = $wpdb->prefix . 'mongike_logs';

    $logs = $wpdb->get_results("SELECT * FROM $table ORDER BY id DESC LIMIT 100");

    echo '<div class="wrap"><h1>Mongike Logs</h1>';
    echo '<table class="widefat"><thead><tr><th>Time</th><th>Log</th></tr></thead><tbody>';

    foreach ($logs as $log) {
        echo '<tr>';
        echo '<td>'.$log->created_at.'</td>';
        echo '<td><pre>'.esc_html(print_r(maybe_unserialize($log->log), true)).'</pre></td>';
        echo '</tr>';
    }

    echo '</tbody></table></div>';
}