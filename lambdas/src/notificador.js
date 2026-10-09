'use strict';

const { SNSClient, PublishCommand } = require('@aws-sdk/client-sns');

const sns = new SNSClient({});

const ETIQUETAS = {
  accidente: 'Accidente',
  congestion: 'Congestión',
  desvio: 'Desvío',
  obra: 'Obra en la vía',
  falla: 'Falla del vehículo',
  clima: 'Clima',
  otro: 'Incidente',
};

// Publica el aviso en SNS con el atributo "ruta": cada suscriptor solo recibe
// los de sus rutas favoritas (política de filtro de la suscripción).
async function procesar(record) {
  const e = JSON.parse(record.body);
  const etiqueta = ETIQUETAS[e.tipo] || 'Incidente';
  const asunto = `${etiqueta} en ${e.rutaNombre || e.rutaId}`.slice(0, 100);
  const lineas = [
    `${etiqueta} en la ruta "${e.rutaNombre || e.rutaId}".`,
    e.descripcion,
    e.ubicacion ? `Ubicación: ${e.ubicacion}` : null,
    `Reportado: ${e.ts}`,
  ].filter(Boolean);

  await sns.send(new PublishCommand({
    TopicArn: process.env.TOPIC_ARN,
    Subject: asunto,
    Message: lineas.join('\n'),
    MessageAttributes: {
      ruta: { DataType: 'String', StringValue: e.rutaId },
      tipo: { DataType: 'String', StringValue: e.tipo || 'otro' },
    },
  }));
  console.log(JSON.stringify({ msg: 'aviso publicado', incidente: e.id, ruta: e.rutaId }));
}

// Un fallo reintenta solo ese mensaje; tras 3 intentos va a la DLQ.
exports.handler = async (event) => {
  const batchItemFailures = [];
  for (const record of event.Records) {
    try {
      await procesar(record);
    } catch (err) {
      console.error(JSON.stringify({ msg: 'falló el aviso', messageId: record.messageId, error: err.message }));
      batchItemFailures.push({ itemIdentifier: record.messageId });
    }
  }
  return { batchItemFailures };
};
