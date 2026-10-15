package com.cuycoders.cuyscout.demo;

import android.app.Activity;
import android.os.Bundle;
import android.text.InputType;
import android.view.View;
import android.widget.*;

/** Offline fixture: no accounts, network, real money or persisted payment state. */
public final class MainActivity extends Activity {
    private LinearLayout page;
    private void screen(String title) {
        page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(24, 64, 24, 24);
        setContentView(page);
        text(title);
        text("DEMO · Datos ficticios · Sin pagos reales");
    }
    private void text(String value) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(20);
        page.addView(view);
    }
    private EditText field(int id, String hint, int inputType) {
        EditText view = new EditText(this);
        view.setId(id);
        view.setHint(hint);
        view.setInputType(inputType);
        view.setSingleLine(true);
        page.addView(view);
        return view;
    }
    private void button(int id, String title, View.OnClickListener action) {
        Button view = new Button(this);
        view.setId(id);
        view.setText(title);
        view.setOnClickListener(action);
        page.addView(view);
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        screen("CuyScout Demo — Iniciar sesión");
        EditText user = field(R.id.username, "Usuario de prueba", InputType.TYPE_CLASS_TEXT);
        button(R.id.login, "Iniciar sesión", v -> {
            if (user.getText().toString().equals("demo")) home();
            else user.setError("Usa demo");
        });
    }
    private void home() {
        screen("Bienvenido, Demo");
        button(R.id.pay, "Pagar recibo", v -> payment());
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            button(R.id.notifications, "Activar notificaciones", v -> requestPermissions(
                new String[]{"android.permission.POST_NOTIFICATIONS"}, 1));
        }
    }
    private void payment() {
        screen("Pagar — Servicio de prueba");
        EditText amount = field(R.id.amount, "Importe", InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        button(R.id.continue_payment, "Continuar", v -> {
            if (!amount.getText().toString().equals("12.50")) { amount.setError("Usa 12.50"); return; }
            screen("Confirmar pago");
            text("Servicio de prueba · S/ 12.50");
            button(R.id.confirm_payment, "Confirmar pago ficticio", confirm -> {
                screen("Comprobante");
                TextView receipt = new TextView(this);
                receipt.setId(R.id.receipt);
                receipt.setText("Pago completado · Operación DEMO-0001 · S/ 12.50");
                page.addView(receipt);
            });
        });
    }
}
