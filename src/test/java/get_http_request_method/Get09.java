package get_http_request_method;

import base_urls.HerokuappBaseUrl;
import io.restassured.response.Response;
import org.junit.Test;

import java.util.HashMap;
import java.util.Map;

import static io.restassured.RestAssured.given;
import static org.junit.Assert.assertEquals;

public class Get09 extends HerokuappBaseUrl {


     /*
        When
	 		I send GET Request to https://restful-booker.herokuapp.com/booking/2
	 	Then
	 		Response body should be like that;
	 		{
            "firstname": "Mark",
            "lastname": "Wilson",
            "totalprice": 530,
            "depositpaid": false,
            "bookingdates": {
                "checkin": "2017-10-18",
                "checkout": "2019-08-29"
            }
}

     */



    @Test
    public void get09(){

        //Set the url
        spec.pathParams("bir" , "booking", "iki", 2);


        //Set the expected data


        Map<String, Object> bookingdates = new HashMap<>();

        bookingdates.put("checkin","2018-01-01");
        bookingdates.put("checkout","2019-01-01");

        Map<String, Object> expectedData = new HashMap<>();

        expectedData.put("firstname", "James");
        expectedData.put("lastname", "Brown");
        expectedData.put("totalprice",111);
        expectedData.put("depositpaid", true);
        expectedData.put("bookingdates", bookingdates);


        //Send the Get Request and Get the response
        Response response = given().spec(spec).when().get("/{bir}/{iki}");

        response.prettyPrint();

        Map<String, Object> actualData = response.as(HashMap.class);



        assertEquals("Datalar bir biri ile uyumlu degil!",expectedData.get("firstname"), actualData.get("firstname") );
        assertEquals("Datalar bir biri ile uyumlu degil!",expectedData.get("lastname"), actualData.get("lastname") );
        assertEquals("Datalar bir biri ile uyumlu degil!",expectedData.get("totalprice"), actualData.get("totalprice") );
        assertEquals("Datalar bir biri ile uyumlu degil!",expectedData.get("depositpaid"), actualData.get("depositpaid") );

        assertEquals("Datalar bir biri ile uyumlu degil!",bookingdates, actualData.get("bookingdates") );

        assertEquals("Datalar bir biri ile uyumlu degil!",bookingdates.get("checkin"),((Map) actualData.get("bookingdates")).get("checkin") );
        assertEquals("Datalar bir biri ile uyumlu degil!",bookingdates.get("checkout"),((Map) actualData.get("bookingdates")).get("checkout") );

    }



}
